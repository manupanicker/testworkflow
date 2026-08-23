[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName = 'ctxmedia',

    [Parameter(Mandatory = $false)]
    [string]$StorageContainer = 'cvad',

    [Parameter(Mandatory = $false)]
    [string]$BlobPrefix = '',

    [Parameter(Mandatory = $false)]
    [string]$LocalMediaRoot = 'C:\Source\CVADInstaller'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

Write-Host '============================================================'
Write-Host ' Citrix Delivery Controller Installation'
Write-Host '============================================================'
Write-Host ('Storage account : https://' + $StorageAccountName + '.blob.core.windows.net/' + $StorageContainer)
Write-Host ('Blob prefix     : ' + $BlobPrefix)
Write-Host ('Local media     : ' + $LocalMediaRoot)
Write-Host 'SQL Express     : NOT installed (/nosql)'
Write-Host ''

# ===========================================================================
# FUNCTION: Get-AzCopy
# ===========================================================================
function Get-AzCopy {
    param(
        [Parameter(Mandatory = $true)] [string]$InstallPath
    )

    $azcopyExe = Join-Path $InstallPath 'azcopy.exe'

    if (Test-Path -LiteralPath $azcopyExe) {
        Write-Host ('azcopy already present: ' + $azcopyExe)
        return $azcopyExe
    }

    Write-Host 'azcopy not found - downloading...'
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

    $azcopyZip   = Join-Path $InstallPath 'azcopy.zip'
    $extractPath = Join-Path $InstallPath 'extracted'

    Invoke-WebRequest `
        -Uri 'https://aka.ms/downloadazcopy-v10-windows' `
        -OutFile $azcopyZip `
        -UseBasicParsing

    Write-Host 'Extracting azcopy...'
    Expand-Archive -Path $azcopyZip -DestinationPath $extractPath -Force

    $exe = Get-ChildItem -Path $extractPath -Filter 'azcopy.exe' -Recurse |
           Select-Object -First 1

    if ($null -eq $exe) {
        throw 'azcopy.exe not found after extraction.'
    }

    Copy-Item -Path $exe.FullName -Destination $azcopyExe -Force
    Write-Host ('azcopy installed: ' + $azcopyExe)
    return $azcopyExe
}

# ===========================================================================
# FUNCTION: Invoke-AzCopyDownload
# ===========================================================================
function Invoke-AzCopyDownload {
    param(
        [Parameter(Mandatory = $true)] [string]$AzCopyExe,
        [Parameter(Mandatory = $true)] [string]$SourceUrl,
        [Parameter(Mandatory = $true)] [string]$Destination
    )

    $env:AZCOPY_AUTO_LOGIN_TYPE  = 'MSI'
    $env:AZCOPY_CONCURRENCY_VALUE = 'AUTO'

    Write-Host ('Source      : ' + $SourceUrl)
    Write-Host ('Destination : ' + $Destination)
    Write-Host 'Starting azcopy download...'

    $azcopyArgs = @(
        'copy',
        $SourceUrl,
        $Destination,
        '--recursive',
        '--overwrite', 'ifSourceNewer',
        '--log-level', 'INFO'
    )

    $process = Start-Process `
        -FilePath     $AzCopyExe `
        -ArgumentList $azcopyArgs `
        -Wait `
        -PassThru `
        -NoNewWindow

    Write-Host ('azcopy exit code: ' + $process.ExitCode)

    if ($process.ExitCode -ne 0) {
        throw ('FATAL: azcopy failed with exit code ' + $process.ExitCode)
    }
}

# ===========================================================================
# FUNCTION: Test-CitrixServicesRunning
# ===========================================================================
function Test-CitrixServicesRunning {

    $expectedServices = @(
        'CitrixBrokerService',
        'CitrixConfigurationService',
        'CitrixADIdentityService'
    )

    $allRunning = $true

    foreach ($svcName in $expectedServices) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue

        if ($null -eq $svc) {
            Write-Host ('  [MISSING] ' + $svcName)
            $allRunning = $false
        }
        elseif ($svc.Status -ne 'Running') {
            Write-Host ('  [STOPPED] ' + $svcName + ' - attempting start...')
            Start-Service -Name $svcName -ErrorAction SilentlyContinue
            $svc.Refresh()
            Write-Host ('  [STATUS ] ' + $svcName + ' -> ' + $svc.Status)
            if ($svc.Status -ne 'Running') { $allRunning = $false }
        }
        else {
            Write-Host ('  [RUNNING] ' + $svcName)
        }
    }

    return $allRunning
}

# ===========================================================================
# MAIN
# ===========================================================================

# Ensure local media root exists
if (-not (Test-Path -LiteralPath $LocalMediaRoot)) {
    Write-Host ('Creating local media directory: ' + $LocalMediaRoot)
    New-Item -ItemType Directory -Path $LocalMediaRoot -Force | Out-Null
}

# Download media only if installer not already present
$installer = Join-Path $LocalMediaRoot 'x64\XenDesktop Setup\XenDesktopServerSetup.exe'

if (-not (Test-Path -LiteralPath $installer)) {
    Write-Host 'Installer not found locally - downloading media from Blob Storage...'
    $azcopyExe = Get-AzCopy -InstallPath 'C:\azcopy'

    # Wildcard /* copies container CONTENTS directly into destination
    # without creating a container-named subfolder
    $sourceUrl = 'https://' + $StorageAccountName + '.blob.core.windows.net/' + $StorageContainer + '/*'

    Invoke-AzCopyDownload `
        -AzCopyExe   $azcopyExe `
        -SourceUrl   $sourceUrl `
        -Destination $LocalMediaRoot

    Write-Host 'Media download complete.'
    Write-Host ''
}
else {
    Write-Host 'Installer already present - skipping download.'
    Write-Host ''
}

# Search for installer if not at expected path
if (-not (Test-Path -LiteralPath $installer)) {
    Write-Host 'Searching for installer recursively...'
    $candidate = Get-ChildItem `
        -Path    $LocalMediaRoot `
        -Filter  'XenDesktopServerSetup.exe' `
        -File `
        -Recurse |
        Select-Object -First 1

    if ($null -eq $candidate) {
        throw ('FATAL: XenDesktopServerSetup.exe not found under ' + $LocalMediaRoot)
    }

    $installer = $candidate.FullName
}

Write-Host ('Installer path: ' + $installer)
Write-Host ''

# Installer arguments
$arguments = @(
    '/components',              'controller,desktopstudio',
    '/configure_firewall',
    '/nosql',
    '/disableexperiencemetrics',
    '/quiet',
    '/noreboot'
)

# Run the installer
Write-Host 'Running Citrix DDC installer...'
Write-Host ('Command: ' + $installer + ' ' + ($arguments -join ' '))
Write-Host ''

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$process = Start-Process `
    -FilePath     $installer `
    -ArgumentList $arguments `
    -Wait `
    -PassThru `
    -NoNewWindow

$stopwatch.Stop()

Write-Host ('Installer exit code : ' + $process.ExitCode)
Write-Host ('Elapsed time        : ' + $stopwatch.Elapsed.ToString('hh\:mm\:ss'))
Write-Host ''

if ($process.ExitCode -eq 0) {

    Write-Host 'Installer reported success. Verifying Citrix services...'

    if (Test-CitrixServicesRunning) {
        Write-Host ''
        Write-Host '============================================================'
        Write-Host ' Citrix Delivery Controller installed successfully.'
        Write-Host ('  VM hostname : ' + $env:COMPUTERNAME)
        Write-Host ('  Timestamp   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' UTC')
        Write-Host ('  Duration    : ' + $stopwatch.Elapsed.ToString('hh\:mm\:ss'))
        Write-Host '============================================================'
        Write-Host 'INSTALL_COMPLETE'
    }
    else {
        throw 'FATAL: Installer exited 0 but one or more Citrix services failed to start.'
    }

}
elseif ($process.ExitCode -eq 14 -or $process.ExitCode -eq 3) {

    Write-Host ('Exit code ' + $process.ExitCode + ' - checking if services are already running from a previous pass...')

    if (Test-CitrixServicesRunning) {
        Write-Host ''
        Write-Host '============================================================'
        Write-Host ' Citrix Delivery Controller services are running.'
        Write-Host ('  VM hostname : ' + $env:COMPUTERNAME)
        Write-Host ('  Timestamp   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' UTC')
        Write-Host '============================================================'
        Write-Host 'INSTALL_COMPLETE'
    }
    else {
        Write-Host 'REBOOT_REQUIRED: Installer requires a reboot to continue.'
    }

}
else {
    throw ('FATAL: Installer failed with exit code ' + $process.ExitCode)
}
