[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName = 'ctxmedia',

    [Parameter(Mandatory = $false)]
    [string]$StorageContainer = 'cvad',

    [Parameter(Mandatory = $false)]
    [string]$BlobPrefix = 'x64/',

    [Parameter(Mandatory = $false)]
    [string]$LocalMediaRoot = 'C:\Source\CitrixCVAD'
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
# Downloads azcopy if not already present on the VM.
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

    $azcopyZip = Join-Path $InstallPath 'azcopy.zip'
    $extractPath = Join-Path $InstallPath 'extracted'

    Invoke-WebRequest `
        -Uri 'https://aka.ms/downloadazcopy-v10-windows' `
        -OutFile $azcopyZip `
        -UseBasicParsing

    Write-Host 'Extracting azcopy...'
    Expand-Archive -Path $azcopyZip -DestinationPath $extractPath -Force

    $exe = Get-ChildItem `
        -Path    $extractPath `
        -Filter  'azcopy.exe' `
        -Recurse |
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
# Uses azcopy with VM managed identity to download blobs recursively.
# ===========================================================================
function Invoke-AzCopyDownload {
    param(
        [Parameter(Mandatory = $true)] [string]$AzCopyExe,
        [Parameter(Mandatory = $true)] [string]$SourceUrl,
        [Parameter(Mandatory = $true)] [string]$Destination
    )

    # MSI tells azcopy to use the VM managed identity automatically
    $env:AZCOPY_AUTO_LOGIN_TYPE = 'MSI'

    # Suppress azcopy telemetry prompt
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
        throw ('azcopy failed with exit code ' + $process.ExitCode + '. Verify managed identity has Storage Blob Data Reader on the container.')
    }
}

# ===========================================================================
# MAIN
# ===========================================================================

# Ensure local media root exists
if (-not (Test-Path -LiteralPath $LocalMediaRoot)) {
    Write-Host ('Creating local media directory: ' + $LocalMediaRoot)
    New-Item -ItemType Directory -Path $LocalMediaRoot -Force | Out-Null
}

# Step 1 - Get azcopy
$azcopyExe = Get-AzCopy -InstallPath 'C:\azcopy'

# Step 2 - Build source URL
# Trailing * tells azcopy to copy contents of the prefix, not the prefix folder itself
$sourceUrl = 'https://' + $StorageAccountName + '.blob.core.windows.net/' + $StorageContainer + '/' + $BlobPrefix + '*'

# Step 3 - Download media
Invoke-AzCopyDownload `
    -AzCopyExe   $azcopyExe `
    -SourceUrl   $sourceUrl `
    -Destination $LocalMediaRoot

Write-Host ''
Write-Host 'Media download complete.'
Write-Host ''

# Step 4 - Locate installer
$installer = Join-Path $LocalMediaRoot 'XenDesktop Setup\XenDesktopServerSetup.exe'

if (-not (Test-Path -LiteralPath $installer)) {
    Write-Host 'Installer not found at expected path - searching recursively...'
    $candidate = Get-ChildItem `
        -Path    $LocalMediaRoot `
        -Filter  'XenDesktopServerSetup.exe' `
        -File `
        -Recurse |
        Select-Object -First 1

    if ($null -eq $candidate) {
        throw ('XenDesktopServerSetup.exe not found under ' + $LocalMediaRoot + '. Verify the x64/ media structure in Blob Storage.')
    }

    $installer = $candidate.FullName
}

Write-Host ('Installer path: ' + $installer)
Write-Host ''

# Step 5 - Run installer
$arguments = @(
    '/components',              'controller,desktopstudio',
    '/configure_firewall',
    '/nosql',
    '/disableexperiencemetrics',
    '/quiet',
    '/noreboot'
)

Write-Host 'Starting Citrix Delivery Controller installation...'
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

if ($process.ExitCode -ne 0) {
    throw ('Citrix Delivery Controller installer failed with exit code ' + $process.ExitCode)
}

# Step 6 - Verify services
Write-Host ''
Write-Host 'Verifying Citrix services...'

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

if (-not $allRunning) {
    throw 'One or more Citrix services failed to start. Review service status above.'
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' Citrix Delivery Controller installation completed successfully.'
Write-Host ('  VM hostname : ' + $env:COMPUTERNAME)
Write-Host ('  Timestamp   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' UTC')
Write-Host ('  Duration    : ' + $stopwatch.Elapsed.ToString('hh\:mm\:ss'))
Write-Host '============================================================'
