[CmdletBinding()]
param(
    [string]$StorageAccountName = 'ctxmedia',
    [string]$StorageContainer = 'cvad',
    [string]$BlobPrefix = '',
    [string]$LocalMediaRoot = 'C:\Source\CVADInstaller',
    [string]$InstallerName = 'SessionRecordingServer.msi'
)
$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
function Get-AzCopy { param([string]$InstallPath); $e=Join-Path $InstallPath 'azcopy.exe'; if(Test-Path $e){return $e}; New-Item -ItemType Directory -Path $InstallPath -Force|Out-Null; $z=Join-Path $InstallPath 'azcopy.zip'; $x=Join-Path $InstallPath 'extracted'; Invoke-WebRequest 'https://aka.ms/downloadazcopy-v10-windows' -OutFile $z -UseBasicParsing; Expand-Archive $z $x -Force; $f=Get-ChildItem $x -Filter azcopy.exe -Recurse|Select-Object -First 1; if(!$f){throw 'azcopy.exe not found'}; Copy-Item $f.FullName $e -Force; return $e }
function Get-Media { param([string]$Exe,[string]$Source,[string]$Destination); $env:AZCOPY_AUTO_LOGIN_TYPE='MSI'; $env:AZCOPY_CONCURRENCY_VALUE='AUTO'; $p=Start-Process $Exe -ArgumentList @('copy',$Source,$Destination,'--recursive','--overwrite','ifSourceNewer','--log-level','INFO') -Wait -PassThru -NoNewWindow; if($p.ExitCode-ne 0){throw "FATAL: azcopy failed with exit code $($p.ExitCode)"} }
New-Item -ItemType Directory -Path $LocalMediaRoot -Force|Out-Null
$i=Get-ChildItem $LocalMediaRoot -Filter $InstallerName -File -Recurse -ErrorAction SilentlyContinue|Select-Object -First 1
if(!$i){$a=Get-AzCopy 'C:\azcopy'; Get-Media $a "https://$StorageAccountName.blob.core.windows.net/$StorageContainer/*" $LocalMediaRoot; $i=Get-ChildItem $LocalMediaRoot -Filter $InstallerName -File -Recurse|Select-Object -First 1}
if(!$i){throw "FATAL: $InstallerName not found under $LocalMediaRoot"}
Write-Host "Session Recording installer: $($i.FullName)"
if($i.Extension -ieq '.msi'){$p=Start-Process 'msiexec.exe' -ArgumentList @('/i',$i.FullName,'/qn','/norestart') -Wait -PassThru -NoNewWindow} else {$p=Start-Process $i.FullName -ArgumentList @('/quiet','/noreboot') -Wait -PassThru -NoNewWindow}
Write-Host "Installer exit code: $($p.ExitCode)"
if($p.ExitCode -in @(0)){Write-Host 'INSTALL_COMPLETE'} elseif($p.ExitCode -in @(3,14,3010,1641)){Write-Host "REBOOT_REQUIRED: exit code $($p.ExitCode)"} else {throw "FATAL: Session Recording installer failed with exit code $($p.ExitCode)"}
