[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DomainName,

    [Parameter(Mandatory)]
    [string]$DomainUsername,

    [Parameter(Mandatory)]
    [string]$DomainPassword
)

$ErrorActionPreference = 'Stop'

$computerSystem = Get-CimInstance Win32_ComputerSystem
Write-Output "Computer: $($computerSystem.Name)"
Write-Output "Domain: $($computerSystem.Domain)"
Write-Output "PartOfDomain: $($computerSystem.PartOfDomain)"

if (-not $computerSystem.PartOfDomain) {
    Write-Output "Computer is already not domain joined. Nothing to do."
    exit 0
}

if ($computerSystem.Domain -ne $DomainName) {
    throw "Computer is joined to '$($computerSystem.Domain)', not '$DomainName'. Refusing to unjoin the machine."
}

$securePassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
$credential = [System.Management.Automation.PSCredential]::new($DomainUsername, $securePassword)

Write-Output "Removing computer from domain '$DomainName' and restarting..."

Remove-Computer `
    -UnjoinDomainCredential $credential `
    -Force `
    -Restart `
    -ErrorAction Stop
