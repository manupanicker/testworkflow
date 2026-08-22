[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MediaUri,

    [Parameter(Mandatory = $false)]
    [string]$MediaSasToken
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$WorkRoot = 'C:\Temp\CitrixLicensing'
$DownloadPath = Join-Path $WorkRoot 'CitrixMedia.zip'
$ExtractRoot = Join-Path $WorkRoot 'CVAD'
$Installer = Join-Path $ExtractRoot 'x64\Licensing\CitrixLicensing.exe'
$LogFile = 'C:\Temp\CitrixLicenseInstall.log'

Write-Output '============================================================'
Write-Output 'Citrix License Server Installation'
Write-Output '============================================================'
Write-Output "Media URI : $MediaUri"

New-Item -Path $WorkRoot -ItemType Directory -Force | Out-Null

# If Licensing is already installed, do not reinstall it.
$ExistingServices = @(
    'Citrix Licensing',
    'CitrixWebServicesforLicensing',
    'CitrixLicensingSupportService'
) | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue } | Where-Object { $null -ne $_ }

if ($ExistingServices) {
    Write-Output 'Citrix Licensing is already installed. Skipping installation.'
}
else {
    if ([string]::IsNullOrWhiteSpace($MediaUri)) {
        throw 'MediaUri is required when Citrix Licensing is not already installed.'
    }

    $Uri = $MediaUri
    if (-not [string]::IsNullOrWhiteSpace($MediaSasToken)) {
        $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
        $Uri = "$Uri$separator$MediaSasToken"
    }

    Write-Output 'Downloading Citrix media...'
    Invoke-WebRequest -Uri $Uri -OutFile $DownloadPath -UseBasicParsing

    if (-not (Test-Path $DownloadPath)) {
        throw "Citrix media download failed: $DownloadPath"
    }

    Write-Output 'Extracting Citrix media...'
    if (Test-Path $ExtractRoot) {
        Remove-Item $ExtractRoot -Recurse -Force
    }

    Expand-Archive -Path $DownloadPath -DestinationPath $ExtractRoot -Force

    # Support a zip that contains an additional top-level directory.
    if (-not (Test-Path $Installer)) {
        $FoundInstaller = Get-ChildItem -Path $ExtractRoot -Filter 'CitrixLicensing.exe' -File -Recurse | Select-Object -First 1
        if ($FoundInstaller) {
            $Installer = $FoundInstaller.FullName
        }
    }

    if (-not (Test-Path $Installer)) {
        throw "CitrixLicensing.exe was not found under $ExtractRoot"
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

$ServiceNames = @(
    'Citrix Licensing',
    'CitrixWebServicesforLicensing',
    'CitrixLicensingSupportService'
)

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

$FinalServices = Get-Service -Name $ServiceNames -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType
$FinalServices | Format-Table -AutoSize | Out-String | Write-Output

$Stopped = $FinalServices | Where-Object { $_.Status -ne 'Running' }
if ($Stopped) {
    throw "One or more Citrix Licensing services are not running: $($Stopped.Name -join ', ')"
}

Write-Output 'Citrix Licensing installation and validation completed successfully.'

# Cleanup only the downloaded/extracted installation media.
Remove-Item -Path $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'Installation media cleaned up.'
