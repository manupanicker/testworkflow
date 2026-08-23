[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName = 'ctxmedia',

    [Parameter(Mandatory = $false)]
    [string]$StorageContainer = 'cvad',

    [Parameter(Mandatory = $false)]
    [string]$BlobPrefix = 'x64/',

    [Parameter(Mandatory = $false)]
    [string]$LocalMediaRoot = 'C:\Source\CitrixCVAD',

    [Parameter(Mandatory = $false)]
    [bool]$InstallSqlExpress = $false
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host '============================================================'
Write-Host 'Citrix Delivery Controller Installation'
Write-Host '============================================================'
Write-Host "Source      : Azure Blob Storage"
Write-Host "Container   : $StorageContainer"
Write-Host "Blob prefix : $BlobPrefix"
Write-Host "Local media : $LocalMediaRoot"
Write-Host "SQL Express : $InstallSqlExpress"
Write-Host ''

function Get-ManagedIdentityToken {
    $tokenUri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F'

    Write-Host 'Requesting Azure Storage token from VM managed identity...'

    $response = Invoke-RestMethod `
        -Method Get `
        -Uri $tokenUri `
        -Headers @{ Metadata = 'true' } `
        -UseBasicParsing

    if ([string]::IsNullOrWhiteSpace($response.access_token)) {
        throw 'Managed identity token was not returned by the Azure Instance Metadata Service.'
    }

    return $response.access_token
}

function Get-BlobList {
    param(
        [Parameter(Mandatory = $true)] [string]$Token,
        [Parameter(Mandatory = $true)] [string]$Account,
        [Parameter(Mandatory = $true)] [string]$Container,
        [Parameter(Mandatory = $true)] [string]$Prefix
    )

    $allBlobs = [System.Collections.Generic.List[string]]::new()
    $marker = $null

    do {
        $uri = "https://$Account.blob.core.windows.net/$Container?restype=container&comp=list&prefix=$([uri]::EscapeDataString($Prefix))"

        if (-not [string]::IsNullOrWhiteSpace($marker)) {
            $uri += "&marker=$([uri]::EscapeDataString($marker))"
        }

        $response = Invoke-RestMethod `
            -Method Get `
            -Uri $uri `
            -Headers @{
                Authorization = "Bearer $Token"
                'x-ms-version' = '2023-11-03'
            } `
            -UseBasicParsing

        foreach ($blob in @($response.EnumerationResults.Blobs.Blob)) {
            if ($null -ne $blob.Name -and -not [string]::IsNullOrWhiteSpace([string]$blob.Name)) {
                $allBlobs.Add([string]$blob.Name)
            }
        }

        $marker = [string]$response.EnumerationResults.NextMarker
    } while (-not [string]::IsNullOrWhiteSpace($marker))

    return $allBlobs.ToArray()
}

function ConvertTo-BlobUriPath {
    param(
        [Parameter(Mandatory = $true)] [string]$BlobName
    )

    # Encode each path segment while preserving the blob's '/' separators.
    return (($BlobName -split '/') | ForEach-Object {
        [Uri]::EscapeDataString($_)
    }) -join '/'
}

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
    $uri = "https://$Account.blob.core.windows.net/$Container/$encodedBlobName"

    Invoke-WebRequest `
        -Method Get `
        -Uri $uri `
        -Headers @{
            Authorization = "Bearer $Token"
            'x-ms-version' = '2023-11-03'
        } `
        -OutFile $Destination `
        -UseBasicParsing
}

if (-not (Test-Path -LiteralPath $LocalMediaRoot)) {
    New-Item -ItemType Directory -Path $LocalMediaRoot -Force | Out-Null
}

$token = Get-ManagedIdentityToken
Write-Host 'Managed identity authentication succeeded.'
Write-Host ''

Write-Host 'Listing Citrix CVAD media in Blob Storage...'
$blobNames = @(Get-BlobList `
    -Token $token `
    -Account $StorageAccountName `
    -Container $StorageContainer `
    -Prefix $BlobPrefix)

if ($blobNames.Count -eq 0) {
    throw "No blobs were found under prefix '$BlobPrefix'."
}

Write-Host "Found $($blobNames.Count) blob(s)."

foreach ($blobName in $blobNames) {
    $relativePath = $blobName.Substring($BlobPrefix.Length)
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        continue
    }

    $relativePath = $relativePath.Replace('/', '\\')
    $destination = Join-Path $LocalMediaRoot $relativePath

    Write-Host "Downloading: $blobName"
    Download-Blob `
        -Token $token `
        -Account $StorageAccountName `
        -Container $StorageContainer `
        -BlobName $blobName `
        -Destination $destination
}

$installer = Join-Path $LocalMediaRoot 'XenDesktop Setup\XenDesktopServerSetup.exe'

if (-not (Test-Path -LiteralPath $installer)) {
    $candidate = Get-ChildItem -Path $LocalMediaRoot -Filter 'XenDesktopServerSetup.exe' -File -Recurse | Select-Object -First 1
    if ($null -eq $candidate) {
        throw "XenDesktopServerSetup.exe was not found under $LocalMediaRoot."
    }
    $installer = $candidate.FullName
}

Write-Host ''
Write-Host "Delivery Controller installer: $installer"

$arguments = @(
    '/components', 'controller,desktopstudio',
    '/configure_firewall',
    '/quiet',
    '/noreboot'
)

if (-not $InstallSqlExpress) {
    $arguments += '/nosql'
}

Write-Host 'Starting Citrix Delivery Controller installation...'
Write-Host "Command: $installer $($arguments -join ' ')"

$process = Start-Process `
    -FilePath $installer `
    -ArgumentList $arguments `
    -Wait `
    -PassThru `
    -NoNewWindow

Write-Host "Installer exit code: $($process.ExitCode)"

if ($process.ExitCode -ne 0) {
    throw "Citrix Delivery Controller installer failed with exit code $($process.ExitCode)."
}

Write-Host ''
Write-Host 'Citrix Delivery Controller installation completed successfully.'
Write-Host '============================================================'
