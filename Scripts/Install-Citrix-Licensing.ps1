[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CitrixMediaPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$WorkRoot = 'C:\Temp\CitrixLicensing'
$MediaRoot = Join-Path $WorkRoot 'CVAD'
$Installer = Join-Path $MediaRoot 'x64\Licensing\CitrixLicensing.exe'
$LogFile = 'C:\Temp\CitrixLicenseInstall.log'

Write-Output '============================================================'
Write-Output 'Citrix License Server Installation'
Write-Output '============================================================'
Write-Output "Media path : $CitrixMediaPath"

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
    if ([string]::IsNullOrWhiteSpace($CitrixMediaPath)) {
        throw 'CitrixMediaPath is required when Citrix Licensing is not already installed.'
    }

    if (-not (Test-Path -LiteralPath $CitrixMediaPath)) {
        throw "Citrix media path is not accessible from the target VM: $CitrixMediaPath"
    }

    Write-Output 'Copying Citrix media from UNC share...'
    Copy-Item -Path (Join-Path $CitrixMediaPath '*') -Destination $MediaRoot -Recurse -Force

    # Support media layouts with an additional top-level directory.
    if (-not (Test-Path -LiteralPath $Installer)) {
        $FoundInstaller = Get-ChildItem -Path $MediaRoot -Filter 'CitrixLicensing.exe' -File -Recurse | Select-Object -First 1
        if ($FoundInstaller) {
            $Installer = $FoundInstaller.FullName
        }
    }

    if (-not (Test-Path -LiteralPath $Installer)) {
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

# Cleanup only the copied installation media. Keep the installer log for troubleshooting.
Remove-Item -Path $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'Copied installation media cleaned up.'
