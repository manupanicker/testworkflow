param(
    [Parameter(Mandatory = $true)]
    [string]$DomainName,

    [Parameter(Mandatory = $true)]
    [string]$DomainUsername,

    [Parameter(Mandatory = $true)]
    [string]$DomainPassword
)

$ErrorActionPreference = 'Stop'

Write-Output "=============================================="
Write-Output "Domain Join"
Write-Output "=============================================="
Write-Output "Computer : $env:COMPUTERNAME"
Write-Output "Domain   : $DomainName"

# Confirm the VM is using the expected DNS server and can locate Active Directory.
Write-Output "Checking DNS configuration..."
$dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 |
    Where-Object { $_.ServerAddresses } |
    Select-Object -ExpandProperty ServerAddresses

if ($dnsServers -notcontains '172.16.0.4') {
    throw "Expected DNS server 172.16.0.4 was not found. Current DNS: $($dnsServers -join ', ')"
}

Write-Output "DNS server 172.16.0.4 is configured."

Write-Output "Testing domain DNS..."
Resolve-DnsName $DomainName -ErrorAction Stop | Out-Null
Resolve-DnsName "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -ErrorAction Stop | Out-Null
Write-Output "Active Directory DNS discovery successful."

$computerSystem = Get-CimInstance Win32_ComputerSystem

if ($computerSystem.PartOfDomain) {
    Write-Output "Computer is already domain joined to: $($computerSystem.Domain)"
    exit 0
}

$securePassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
$credential = [System.Management.Automation.PSCredential]::new($DomainUsername, $securePassword)

Write-Output "Joining $env:COMPUTERNAME to $DomainName..."
Add-Computer -DomainName $DomainName -Credential $credential -Force -ErrorAction Stop

Write-Output "Domain join completed."

# Configure Network Discovery/firewall rules so the interactive
# 'Do you want to allow your PC to be discoverable?' prompt is not needed.
Write-Output "Configuring Network Discovery..."

$discoveryRules = Get-NetFirewallRule -DisplayGroup 'Network Discovery' -ErrorAction SilentlyContinue
if ($discoveryRules) {
    $discoveryRules | Set-NetFirewallRule -Enabled True -ErrorAction Stop
    Write-Output "Network Discovery firewall rules enabled."
}
else {
    Write-Output "Network Discovery firewall rule group was not found; continuing."
}

# A domain-joined machine should use the DomainAuthenticated profile automatically.
# Do not force the profile to Private after joining the domain.
$profile = Get-NetConnectionProfile | Select-Object -First 1
if ($profile) {
    Write-Output "Network profile: $($profile.Name) / $($profile.NetworkCategory)"
}

Write-Output "Restarting computer to complete domain membership..."
Restart-Computer -Force
