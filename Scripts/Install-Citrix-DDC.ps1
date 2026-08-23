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
Write-Host "Storage account : https://${StorageAccountName}.blob.core.windows.net/${StorageContainer}"
Write-Host "Blob prefix     : $BlobPrefix"
Write-Host "Local media     : $LocalMediaRoot"
Write-Host "SQL Express     : NOT installed (/nosql)"
Write-Host ''

# ===========================================================================
# FUNCTION: Get-ManagedIdentityToken
# Requests an Azure Storage OAuth token from the VM managed identity via IMDS.
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
# Lists all blobs under a given prefix using the Azure Blob REST API.
# FIX: Variables in URI strings are wrapped in ${} to prevent PowerShell
#      from including the following ? or & characters in the variable name.
# ===========================================================================
function Get-BlobList {
    param(
        [Parameter(Mandatory = $true)] [string]$Token,
        [Parameter(Mandatory = $true)] [string]$Account,
        [Parameter(Mandatory = $true)] [string]$Container,
        [Parameter(Mandatory = $true)] [string]$Prefix
    )

    # Validate container name before building the URI
    if ([string]::IsNullOrWhiteSpace($Container) -or
        $Container -notmatch '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$') {
        throw "Invalid Blob container name: '$Container'. Container name must be lowercase alphanumeric with optional hyphens."
    }

    Write-Host "Listing blobs — account: $Account  container: $Container  prefix: $Prefix"

    $allBlobs = [System.Collections.Generic.List[string]]::new()
    $marker   = $null

    do {
        $encodedPrefix = [Uri]::EscapeDataString($Prefix)

        # CRITICAL FIX: use ${Account} and ${Container} so PowerShell does not
        # try to parse the ? as part of the variable name, which produces a
        # broken URI like /=container&comp=list when Container is empty.
        $uri = "https://${Account}.blob.core.windows.net/${Container}" +
               "?restype=container&comp=list&prefix=${encodedPrefix}"

        if (-not [string]::IsNullOrWhiteSpace($marker)) {
            $uri += "&marker=$([Uri]::EscapeDataString($marker))"
        }

        Write-Host "Listing Blob URI: $uri"

        $response = Invoke-RestMethod `
            -Method Get `
            -Uri $uri `
            -Headers @{
                Authorization  = "Bearer $Token"
                'x-ms-version' = '2023-11-03'
            } `
            -UseBasicParsing

        foreach ($blob in @($response.EnumerationResults.Blobs.Blob)) {
            if ($null -ne $blob.Name -and
                -not [string]::IsNullOrWhiteSpace([string]$blob.Name)) {
                $allBlobs.Add([string]$blob.Name)
            }
        }

        $marker = [string]$response.EnumerationResults.NextMarker

    } while (-not [string]::IsNullOrWhiteSpace($marker))

    return $allBlobs.ToArray()
}

# ===========================================================================
# FUNCTION: ConvertTo-BlobUriPath
# Percent-encodes each path segment of a blob name individually so that
# forward slashes (path separators) are preserved in the URI.
# ===========================================================================
function ConvertTo-BlobUriPath {
    param([Parameter(Mandatory = $true)] [string]$BlobName)

    return (($BlobName -split '/') |
            ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
}

# ===========================================================================
# FUNCTION: Download-Blob
# Downloads a single blob to a local destination path.
# FIX: URI uses ${Account} and ${Container} for the same reason as Get-BlobList.
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

    # CRITICAL FIX: use ${Account} and ${Container}
    $uri = "https://${Account}.blob.core.windows.net/${Container}/${encodedBlobName}"

    Write-Host "Downloading: $BlobName -> $Destination"

    Invoke-WebRequest `
        -Method Get `
        -Uri $uri `
        -Headers @{
            Authorization  = "Bearer $Token"
            'x-ms-version' = '2023-11-03'
        } `
        -OutFile $Destination `
        -UseBasicParsing
}

# ===========================================================================
# MAIN
# ===========================================================================

# Ensure local media root exists
if (-not (Test-Path -LiteralPath $LocalMediaRoot)) {
    Write-Host "Creating local media directory: $LocalMediaRoot"
    New-Item -ItemType Directory -Path $LocalMediaRoot -Force | Out-Null
}

# Authenticate
$token = Get-ManagedIdentityToken
Write-Host 'Managed identity authentication succeeded.'
Write-Host ''

# List blobs
Write-Host 'Listing Citrix CVAD media in Blob Storage...'
$blobNames = @(Get-BlobList `
    -Token     $token `
    -Account   $StorageAccountName `
    -Container $StorageContainer `
    -Prefix    $BlobPrefix)

if ($blobNames.Count -eq 0) {
    throw "No blobs were found under prefix '$BlobPrefix' in container '$StorageContainer'. Verify the media has been uploaded."
}

Write-Host "Found $($blobNames.Count) blob(s). Starting download..."
Write-Host ''

# Download all blobs preserving relative folder structure
foreach ($blobName in $blobNames) {

    $relativePath = $blobName.Substring($BlobPrefix.Length)

    # Skip zero-length relative paths (the prefix folder entry itself)
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

# Locate installer
$installer = Join-Path $LocalMediaRoot 'XenDesktop Setup\XenDesktopServerSetup.exe'

if (-not (Test-Path -LiteralPath $installer)) {
    Write-Host "Installer not found at expected path. Searching recursively..."
    $candidate = Get-ChildItem `
        -Path    $LocalMediaRoot `
        -Filter  'XenDesktopServerSetup.exe' `
        -File `
        -Recurse |
        Select-Object -First 1

    if ($null -eq $candidate) {
        throw "XenDesktopServerSetup.exe was not found under '$LocalMediaRoot'. Verify the media structure in Blob Storage."
    }

    $installer = $candidate.FullName
}

Write-Host "Installer path: $installer"
Write-Host ''

# Build argument list
$arguments = @(
    '/components',              'controller,desktopstudio',
    '/configure_firewall',
    '/nosql',
    '/disableexperiencemetrics',
    '/quiet',
    '/noreboot'
)

Write-Host 'Starting Citrix Delivery Controller installation...'
Write-Host "Command: $installer $($arguments -join ' ')"
Write-Host ''

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$process = Start-Process `
    -FilePath        $installer `
    -ArgumentList    $arguments `
    -Wait `
    -PassThru `
    -NoNewWindow

$stopwatch.Stop()

Write-Host "Installer exit code : $($process.ExitCode)"
Write-Host "Elapsed time        : $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))"

if ($process.ExitCode -ne 0) {
    throw "Citrix Delivery Controller installer failed with exit code $($process.ExitCode)."
}

# Verify key services started
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
        Write-Host "  [MISSING] $svcName"
        $allRunning = $false
    }
    elseif ($svc.Status -ne 'Running') {
        Write-Host "  [STOPPED] $svcName — attempting start..."
        Start-Service -Name $svcName -ErrorAction SilentlyContinue
        $svc.Refresh()
        $status = $svc.Status
        Write-Host "  [STATUS ] $svcName -> $status"
        if ($status -ne 'Running') { $allRunning = $false }
    }
    else {
        Write-Host "  [RUNNING] $svcName"
    }
}

if (-not $allRunning) {
    throw "One or more Citrix services failed to start. Review service status above."
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' Citrix Delivery Controller installation completed successfully.'
Write-Host "  VM hostname : $env:COMPUTERNAME"
Write-Host "  Timestamp   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
Write-Host "  Duration    : $($stopwatch.Elapsed.ToString('hh\:mm\:ss'))"
Write-Host '============================================================'
