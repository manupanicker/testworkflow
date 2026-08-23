[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BlobUrisBase64
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SourceRoot = 'C:\Source'
$MediaRoot = Join-Path $SourceRoot 'CitrixLicensing'
$LogFile = Join-Path $MediaRoot 'CitrixLicenseInstall.log'

Write-Output '============================================================'
Write-Output 'Citrix License Server Installation'
Write-Output '============================================================'
Write-Output 'Source      : Azure Blob Storage'
Write-Output "Local media : $MediaRoot"

if ([string]::IsNullOrWhiteSpace($BlobUrisBase64)) {
    throw 'BlobUrisBase64 is required.'
}

try {
    $BlobUrisJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($BlobUrisBase64))
    $ParsedBlobUris = ConvertFrom-Json -InputObject $BlobUrisJson

    # Always flatten the JSON result into individual URI strings. This also handles
    # a single-element JSON array without producing a nested System.Object[].
    $BlobUris = @($ParsedBlobUris) | ForEach-Object {
        if ($_ -is [System.Array]) {
            $_ | ForEach-Object { [string]$_ }
        }
        else {
            [string]$_
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}
catch {
    throw "BlobUrisBase64 could not be decoded: $($_.Exception.Message)"
}

if (-not $BlobUris -or $BlobUris.Count -eq 0) {
    throw 'No Blob download URLs were supplied.'
}

Write-Output "Received $($BlobUris.Count) Blob download URL(s)."

$ServiceNames = @(
    'Citrix Licensing',
    'CitrixWebServicesforLicensing',
    'CitrixLicensingSupportService'
)

$ExistingServices = $ServiceNames |
    ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue } |
    Where-Object { $null -ne $_ }

if ($ExistingServices) {
    Write-Output 'Citrix Licensing is already installed. Skipping installation.'
}
else {
    New-Item -Path $SourceRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $MediaRoot -ItemType Directory -Force | Out-Null

    foreach ($BlobUri in $BlobUris) {
        try {
            $Uri = [System.Uri]$BlobUri
        }
        catch {
            throw "Invalid Blob download URL received: $BlobUri"
        }

        $BlobPath = $Uri.AbsolutePath.TrimStart('/')
        $SlashIndex = $BlobPath.IndexOf('/')

        if ($SlashIndex -lt 0) {
            throw "Invalid Blob URL path: $BlobUri"
        }

        $BlobName = $BlobPath.Substring($SlashIndex + 1)
        $RelativeName = $BlobName -replace '^Licensing/', ''

        if ([string]::IsNullOrWhiteSpace($RelativeName)) {
            continue
        }

        $LocalFile = Join-Path $MediaRoot $RelativeName
        $LocalDirectory = Split-Path -Path $LocalFile -Parent
        New-Item -Path $LocalDirectory -ItemType Directory -Force | Out-Null

        Write-Output "Downloading: $BlobName"
        Invoke-WebRequest -Uri $Uri -OutFile $LocalFile -UseBasicParsing
    }

    $Installer = Join-Path $MediaRoot 'CitrixLicensing.exe'

    if (-not (Test-Path -LiteralPath $Installer)) {
        $Installer = Get-ChildItem -Path $MediaRoot -Filter 'CitrixLicensing.exe' -File -Recurse |
            Select-Object -First 1 -ExpandProperty FullName
    }

    if ([string]::IsNullOrWhiteSpace($Installer) -or -not (Test-Path -LiteralPath $Installer)) {
        throw "CitrixLicensing.exe was not found under $MediaRoot"
    }

    Write-Output "Installer: $Installer"
    Write-Output 'Installing Citrix License Server...'

    New-Item -Path (Split-Path $LogFile) -ItemType Directory -Force | Out-Null

    $Process = Start-Process `
        -FilePath $Installer `
        -ArgumentList "/quiet /l `"$LogFile`" CEIPOPTIN=NONE" `
        -Wait `
        -PassThru

    $ExitCode = $Process.ExitCode
    Write-Output "Installer exit code: $ExitCode"

    if ($ExitCode -notin @(0, 3010, 1641)) {
        throw "Citrix License Server installation failed with exit code $ExitCode. Check $LogFile"
    }

    if ($ExitCode -eq 3010) {
        Write-Output 'Installation succeeded; reboot required.'
    }
    elseif ($ExitCode -eq 1641) {
        Write-Output 'Installation succeeded and reboot was initiated.'
    }
    else {
        Write-Output 'Installation completed successfully.'
    }
}

Write-Output 'Validating Citrix Licensing services...'

$Services = Get-Service -Name $ServiceNames -ErrorAction SilentlyContinue

if (-not $Services) {
    throw 'No Citrix Licensing services were found after installation.'
}

foreach ($Service in $Services) {
    if ($Service.Status -ne 'Running') {
        Write-Output "Starting service: $($Service.Name)"
        Start-Service -Name $Service.Name -ErrorAction Stop
    }
}

Start-Sleep -Seconds 3

$FinalServices = Get-Service -Name $ServiceNames -ErrorAction SilentlyContinue |
    Select-Object Name, Status, StartType

$FinalServices | Format-Table -AutoSize | Out-String | Write-Output

$Stopped = $FinalServices | Where-Object { $_.Status -ne 'Running' }
if ($Stopped) {
    throw "One or more Citrix Licensing services are not running: $($Stopped.Name -join ', ')"
}

Write-Output 'Citrix Licensing installation and validation completed successfully.'
Write-Output "Citrix Licensing media remains available at $MediaRoot"
