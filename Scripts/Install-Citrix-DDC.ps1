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
# FUNCTION: Get-ManagedIdentityToken
# ===========================================================================
function Get-ManagedIdentityToken {

    $tokenUri = 'http://169.254.169.254/metadata/identity/oauth2/token' +
                '?api-version=2018-02-01' +
                '&resource=https%3A%2F%2Fstorage.azure.com%2F'

    Write-Host 'Requesting Azure Storage token from VM managed identity...'

    $response = Invoke-RestMethod `
        -Method Get `
        -Uri $tokenUri `
        -Headers @{ Metadata = 'true' } `
        -UseBasicParsing

    if ([string]::IsNullOrWhiteSpace($response.access_token)) {
        throw 'Managed identity token was not returned by the Azure Instance Metadata Service.'
    }

    Write-Host 'Managed identity token obtained.'
    return $response.access_token
}

# ===========================================================================
# FUNCTION: Get-BlobList
# ===========================================================================
function Get-BlobList {
    param(
        [Parameter(Mandatory = $true)] [string]$Token,
        [Parameter(Mandatory = $true)] [string]$Account,
        [Parameter(Mandatory = $true)] [string]$Container,
        [Parameter(Mandatory = $true)] [string]$Prefix
    )

    if ([string]::IsNullOrWhiteSpace($Container) -or
        $Container -notmatch '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$') {
        throw ('Invalid Blob container name: ' + $Container)
    }

    Write-Host ('Listing blobs - account: ' + $Account + '  container: ' + $Container + '  prefix: ' + $Prefix)

    $allBlobs = [System.Collections.Generic.List[string]]::new()
    $marker   = $null

    do {
        $encodedPrefix = [Uri]::EscapeDataString($Prefix)

        $uriBase   = 'https://' + $Account + '.blob.core.windows.net/' + $Container
        $uriParams = '?restype=container' + '&comp=list' + '&prefix=' + $encodedPrefix
        $uri       = $uriBase + $uriParams

        if (-not [string]::IsNullOrWhiteSpace($marker)) {
            $uri = $uri + '&marker=' + [Uri]::EscapeDataString($marker)
        }

        Write-Host ('Listing Blob URI: ' + $uri)

        $xmlResponse = Invoke-RestMethod `
            -Method Get `
            -Uri $uri `
            -Headers @{
                Authorization  = ('Bearer ' + $Token)
                'x-ms-version' = '2023-11-03'
            } `
            -UseBasicParsing

        # DEBUG - show raw counts to diagnose empty results
        Write-Host ('Raw blob count   : ' + @($xmlResponse.EnumerationResults.Blobs.Blob).Count)
        Write-Host ('Raw prefix count : ' + @($xmlResponse.EnumerationResults.Blobs.BlobPrefix).Count)
        Write-Host ('Marker           : ' + [string]$xmlResponse.EnumerationResults.NextMarker)

$rawBlobs = $xmlResponse.EnumerationResults.Blobs.Blob
if ($null -ne $rawBlobs) {
    if ($rawBlobs -is [System.Xml.XmlElement]) {
        $allBlobs.Add([string]$rawBlobs.Name)
    }
    else {
        foreach ($blob in $rawBlobs) {
            if ($null -ne $blob.Name -and
                -not [string]::IsNullOrWhiteSpace([string]$blob.Name)) {
                $allBlobs.Add([string]$blob.Name)
            }
        }
    }
}

        $marker = [string]$xmlResponse.EnumerationResults.NextMarker

    } while (-not [string]::IsNullOrWhiteSpace($marker))

    return $allBlobs.ToArray()
}

# ===========================================================================
# FUNCTION: ConvertTo-BlobUriPath
# ===========================================================================
function ConvertTo-BlobUriPath {
    param([Parameter(Mandatory = $true)] [string]$BlobName)

    return (($BlobName -split '/') |
            ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
}

# ===========================================================================
# FUNCTION: Download-Blob
# ===========================================================================
function Download-Blob {
    param(
        [Parameter(Mandatory = $true)] [string]$Token,
        [Parameter(Mandatory = $true)] [string]$Account,
        [Parameter(Mandatory = $true)] [string]$Container,
        [Parameter(Mandatory = $true)] [string]$BlobName,
        [Parameter(Mandatory = $true)] [string]$Destination
    )

    $destinationDirectory = Split-Path -Parent $Destination

    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    $encodedBlobName = ConvertTo-BlobUriPath -BlobName $BlobName
    $uri = 'https://' + $Account + '.blob.core.windows.net/' + $Container + '/' + $encodedBlobName

    Write-Host ('Downloading: ' + $BlobName)

    Invoke-WebRequest `
        -Method Get `
        -Uri $uri `
        -Headers @{
            Authorization  = ('Bearer ' + $Token)
            'x-ms-version' = '2023-11-03'
        } `
        -OutFile $Destination `
        -UseBasicParsing
}

# ===========================================================================
# MAIN
# ===========================================================================

if (-not (Test-Path -LiteralPath $LocalMediaRoot)) {
    Write-Host ('Creating local media directory: ' + $LocalMediaRoot)
    New-Item -ItemType Directory -Path $LocalMediaRoot -Force | Out-Null
}

$token = Get-ManagedIdentityToken
Write-Host 'Managed identity authentication succeeded.'
Write-Host ''

Write-Host 'Listing Citrix CVAD media in Blob Storage...'
$blobNames = @(Get-BlobList `
    -Token     $token `
    -Account   $StorageAccountName `
    -Container $StorageContainer `
    -Prefix    $BlobPrefix)

if ($blobNames.Count -eq 0) {
    throw ('No blobs found under prefix ' + $BlobPrefix + ' in container ' + $StorageContainer + '. Check debug output above for raw counts.')
}

Write-Host ('Found ' + $blobNames.Count + ' blob(s). Starting download...')
Write-Host ''

foreach ($blobName in $blobNames) {

    $relativePath = $blobName.Substring($BlobPrefix.Length)
    if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }

    $relativePath = $relativePath.Replace('/', '\')
    $destination  = Join-Path $LocalMediaRoot $relativePath

    Download-Blob `
        -Token       $token `
        -Account     $StorageAccountName `
        -Container   $StorageContainer `
        -BlobName    $blobName `
        -Destination $destination
}

Write-Host ''
Write-Host 'All blobs downloaded.'
Write-Host ''

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
        throw ('XenDesktopServerSetup.exe was not found under ' + $LocalMediaRoot + '. Verify the media structure in Blob Storage.')
    }

    $installer = $candidate.FullName
}

Write-Host ('Installer path: ' + $installer)
Write-Host ''

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
