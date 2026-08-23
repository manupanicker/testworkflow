[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BlobSasBase64
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$StorageAccount = 'ctxmedia'
$Container = 'cvad'
$BlobPrefix = 'Licensing/'
$SourceRoot = 'C:\Source'
$MediaRoot = Join-Path $SourceRoot 'CitrixLicensing'
$LogFile = Join-Path $MediaRoot 'CitrixLicenseInstall.log'

Write-Output '============================================================'
Write-Output 'Citrix License Server Installation'
Write-Output '============================================================'
Write-Output "Source      : Azure Blob Storage"
Write-Output "Container   : $Container/$BlobPrefix"
Write-Output "Local media : $MediaRoot"

if ([string]::IsNullOrWhiteSpace($BlobSasBase64)) {
    throw 'BlobSasBase64 is required.'
}

try {
    $SasToken = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($BlobSasBase64)).TrimStart('?')
}
catch {
    throw 'BlobSasBase64 is not valid Base64.'
}

if ([string]::IsNullOrWhiteSpace($SasToken)) {
    throw 'Decoded Blob SAS token is empty.'
}

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

    $ContainerBaseUri = "https://$StorageAccount.blob.core.windows.net/$Container"

    Write-Output 'Listing Citrix Licensing media in Blob Storage...'

    # The SAS token is kept separate from the REST query parameters so the
    # Run Command extension does not interpret SAS '&' characters as commands.
    $ListUri = "$ContainerBaseUri`?restype=container&comp=list&prefix=$([Uri]::EscapeDataString($BlobPrefix))&$SasToken"
    $BlobList = Invoke-RestMethod -Uri $ListUri -Method Get -UseBasicParsing
    $Blobs = @($BlobList.EnumerationResults.Blobs.Blob)

    if (-not $Blobs -or $Blobs.Count -eq 0) {
        throw "No blobs were found under '$BlobPrefix' in the Citrix media container."
    }

    foreach ($Blob in $Blobs) {
        $BlobName = [string]$Blob.Name

        if ([string]::IsNullOrWhiteSpace($BlobName) -or $BlobName.EndsWith('/')) {
            continue
        }

        if (-not $BlobName.StartsWith($BlobPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $RelativeName = $BlobName.Substring($BlobPrefix.Length)
        $LocalFile = Join-Path $MediaRoot $RelativeName
        $LocalDirectory = Split-Path -Path $LocalFile -Parent

        New-Item -Path $LocalDirectory -ItemType Directory -Force | Out-Null

        $EncodedBlobName = (($BlobName -split '/') | ForEach-Object {
            [System.Uri]::EscapeDataString($_)
        }) -join '/'

        $DownloadUri = "$ContainerBaseUri/$EncodedBlobName`?$SasToken"

        Write-Output "Downloading: $BlobName"
        Invoke-WebRequest -Uri $DownloadUri -OutFile $LocalFile -UseBasicParsing
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
