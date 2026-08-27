[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName = 'ctxmedia',

    [Parameter(Mandatory = $false)]
    [string]$StorageContainer = 'cvad',

    [Parameter(Mandatory = $false)]
    [string]$BlobPrefix = 'StoreFront/',

    [Parameter(Mandatory = $false)]
    [string]$LocalMediaRoot = 'C:\Source\StoreFrontInstaller',

    [Parameter(Mandatory = $false)]
    [string]$InstallerName = 'StoreFront-x64.exe'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host '============================================================'
Write-Host ' Citrix StoreFront Installation'
Write-Host '============================================================'
Write-Host ('Storage account : https://' + $StorageAccountName + '.blob.core.windows.net/' + $StorageContainer)
Write-Host ('Blob prefix     : ' + $BlobPrefix)
Write-Host ('Local media     : ' + $LocalMediaRoot)
Write-Host ('Installer       : ' + $InstallerName)
Write-Host ''

function Get-AzCopy {
    param([Parameter(Mandatory = $true)] [string]$InstallPath)

    $azcopyExe = Join-Path $InstallPath 'azcopy.exe'

    if (Test-Path -LiteralPath $azcopyExe) {
        Write-Host ('azcopy already present: ' + $azcopyExe)
        return $azcopyExe
    }

    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    $azcopyZip   = Join-Path $InstallPath 'azcopy.zip'
    $extractPath = Join-Path $InstallPath 'extracted'

    Write-Host 'azcopy not found - downloading...'
    Invoke-WebRequest -Uri 'https://aka.ms/downloadazcopy-v10-windows' -OutFile $azcopyZip -UseBasicParsing
    Expand-Archive -Path $azcopyZip -DestinationPath $extractPath -Force

    $exe = Get-ChildItem -Path $extractPath -Filter 'azcopy.exe' -Recurse | Select-Object -First 1
    if ($null -eq $exe) { throw 'azcopy.exe not found after extraction.' }

    Copy-Item -Path $exe.FullName -Destination $azcopyExe -Force
    return $azcopyExe
}

function Invoke-AzCopyDownload {
    param(
        [Parameter(Mandatory = $true)] [string]$AzCopyExe,
        [Parameter(Mandatory = $true)] [string]$SourceUrl,
        [Parameter(Mandatory = $true)] [string]$Destination
    )

    # Use the VM's user-assigned managed identity for Blob authentication,
    # matching the existing DDC installation pattern in this repository.
    $env:AZCOPY_AUTO_LOGIN_TYPE = 'MSI'
    $env:AZCOPY_CONCURRENCY_VALUE = 'AUTO'

    $azcopyArgs = @(
        'copy', $SourceUrl, $Destination,
        '--recursive',
        '--overwrite', 'ifSourceNewer',
        '--log-level', 'INFO'
    )

    $process = Start-Process -FilePath $AzCopyExe -ArgumentList $azcopyArgs -Wait -PassThru -NoNewWindow
    Write-Host ('azcopy exit code: ' + $process.ExitCode)

    if ($process.ExitCode -ne 0) {
        throw ('FATAL: azcopy failed with exit code ' + $process.ExitCode)
    }
}

# StoreFront installer/service names vary by version. The installer itself is
# the authoritative success signal; after installation we also verify that
# StoreFront-related services are present.
function Test-StoreFrontInstallation {
    $services = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Citrix.*StoreFront|Citrix.*Configuration|Citrix.*Credential' }

    if ($services) {
        Write-Host 'StoreFront-related services detected:'
        $services | Select-Object Name, Status, StartType | Format-Table -AutoSize
        return $true
    }

    return $false
}

if (-not (Test-Path -LiteralPath $LocalMediaRoot)) {
    New-Item -ItemType Directory -Path $LocalMediaRoot -Force | Out-Null
}

$installer = Join-Path $LocalMediaRoot $InstallerName

if (-not (Test-Path -LiteralPath $installer)) {
    Write-Host 'StoreFront installer not found locally - downloading media from Blob Storage...'

    $azcopyExe = Get-AzCopy -InstallPath 'C:\azcopy'
    $sourceUrl = 'https://' + $StorageAccountName + '.blob.core.windows.net/' + $StorageContainer + '/' + $BlobPrefix + '*'

    Invoke-AzCopyDownload -AzCopyExe $azcopyExe -SourceUrl $sourceUrl -Destination $LocalMediaRoot
}
else {
    Write-Host 'Installer already present - skipping download.'
}

if (-not (Test-Path -LiteralPath $installer)) {
    Write-Host 'Installer not found at expected path - searching recursively...'
    $candidate = Get-ChildItem -Path $LocalMediaRoot -Filter $InstallerName -File -Recurse | Select-Object -First 1

    if ($null -eq $candidate) {
        throw "FATAL: $InstallerName not found under $LocalMediaRoot. Verify the StoreFront media filename in Blob Storage."
    }

    $installer = $candidate.FullName
}

Write-Host ('Installer path: ' + $installer)
Write-Host ''

# StoreFront setup is launched silently and is prevented from rebooting the VM.
# The workflow handles rebooting separately when required.
$arguments = @('/silent', '/noreboot')

Write-Host 'Running Citrix StoreFront installer...'
Write-Host ('Command: ' + $installer + ' ' + ($arguments -join ' '))

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru -NoNewWindow
$stopwatch.Stop()

Write-Host ('Installer exit code : ' + $process.ExitCode)
Write-Host ('Elapsed time        : ' + $stopwatch.Elapsed.ToString('hh\:mm\:ss'))

if ($process.ExitCode -eq 0) {
    if (Test-StoreFrontInstallation) {
        Write-Host 'StoreFront installation completed successfully.'
        Write-Host ('VM hostname : ' + $env:COMPUTERNAME)
        Write-Host ('Timestamp   : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        Write-Host 'INSTALL_COMPLETE'
    }
    else {
        Write-Host 'Installer returned 0 but StoreFront-related services were not detected yet.'
        Write-Host 'INSTALL_COMPLETE'
    }
}
elseif ($process.ExitCode -in @(3, 14, 3010, 1641)) {
    Write-Host ('REBOOT_REQUIRED: StoreFront installer returned exit code ' + $process.ExitCode)
}
else {
    throw ('FATAL: StoreFront installer failed with exit code ' + $process.ExitCode)
}
