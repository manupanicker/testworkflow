[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,

    [int]$LicenseServerPort = 27000,
    [int]$VendorDaemonPort = 7279,
    [int]$WebServicesPort = 8083,
    [ValidateSet('NONE','DIAGNOSTIC','Unidentified')]
    [string]$CeipOptIn = 'NONE'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    throw "Citrix Licensing installer not found: $InstallerPath"
}

$installer = (Resolve-Path -LiteralPath $InstallerPath).Path

if ((Get-Item $installer).Extension -ine '.exe') {
    throw "Expected CitrixLicensing.exe. Found: $installer"
}

Write-Host "Installing Citrix License Server from $installer"

$args = @(
    '/quiet'
    '/l', 'C:\Windows\Temp\CitrixLicensing-install.log'
    "LSPORT=$LicenseServerPort"
    "VDPORT=$VendorDaemonPort"
    "WSLPORT=$WebServicesPort"
    "CEIPOPTIN=$CeipOptIn"
)

$process = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru

if ($process.ExitCode -ne 0) {
    throw "Citrix Licensing installation failed with exit code $($process.ExitCode). See C:\Windows\Temp\CitrixLicensing-install.log"
}

Write-Host 'Citrix Licensing installer completed successfully.'

$licensePath = 'C:\Program Files (x86)\Citrix\Licensing'
if (-not (Test-Path $licensePath)) {
    $licensePath = 'C:\Program Files\Citrix\Licensing'
}

if (-not (Test-Path $licensePath)) {
    throw 'Citrix Licensing installation directory was not found after installation.'
}

$services = Get-Service -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match 'Citrix.*License|Citrix.*Licensing|Citrix.*WebServices'
}

Write-Host "Citrix Licensing directory: $licensePath"
if ($services) {
    $services | Select-Object Name, Status, StartType | Format-Table -AutoSize
} else {
    Write-Warning 'No Citrix licensing services were discovered by the service-name check. Review the installation log.'
}

Write-Host "License Server port: $LicenseServerPort"
Write-Host "Vendor daemon port: $VendorDaemonPort"
Write-Host "Web Services for Licensing port: $WebServicesPort"
Write-Host 'Citrix Licensing installation validation completed.'
