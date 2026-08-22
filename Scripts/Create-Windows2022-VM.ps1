param(
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $true)]
    [string]$VNetName,

    [Parameter(Mandatory = $true)]
    [string]$SubnetName,

    [Parameter(Mandatory = $true)]
    [string]$VMSize,

    [Parameter(Mandatory = $true)]
    [string]$ImagePublisher,

    [Parameter(Mandatory = $true)]
    [string]$ImageOffer,

    [Parameter(Mandatory = $true)]
    [string]$ImageSku,

    [Parameter(Mandatory = $true)]
    [string]$ImageVersion,

    [Parameter(Mandatory = $true)]
    [string]$OSDiskType,

    [bool]$EnableAcceleratedNetworking = $true,
    [bool]$EnableBootDiagnostics = $true,
    [bool]$EnableAutoUpdates = $true,
    [string]$PatchMode = "AutomaticByOS",
    [string]$SecurityType = "TrustedLaunch",
    [bool]$SecureBoot = $true,
    [bool]$VTPM = $true
)

$ErrorActionPreference = "Stop"

Write-Output "=============================================="
Write-Output "Windows Server 2022 VM Provisioning"
Write-Output "=============================================="
Write-Output "VM Name       : $VMName"
Write-Output "Resource Group: $ResourceGroupName"
Write-Output "Location      : $Location"
Write-Output "VM Size       : $VMSize"
Write-Output "VNet          : $VNetName"
Write-Output "Subnet        : $SubnetName"
Write-Output "Image         : $ImagePublisher/$ImageOffer/$ImageSku"
Write-Output "Security      : $SecurityType"
Write-Output "Secure Boot   : $SecureBoot"
Write-Output "vTPM          : $VTPM"
Write-Output "=============================================="

$context = Get-AzContext
if (-not $context) {
    throw "Azure context is not available."
}

Write-Output "Azure subscription: $($context.Subscription.Name)"

Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null
Write-Output "Resource group verified."

$existingVM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue
if ($existingVM) {
    throw "VM '$VMName' already exists. Stopping to prevent accidental modification."
}

$vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName -ErrorAction Stop
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName -ErrorAction Stop
Write-Output "VNet and subnet verified."

if (-not $env:AZURE_VM_ADMIN_USERNAME) {
    throw "AZURE_VM_ADMIN_USERNAME is not available."
}

if (-not $env:AZURE_VM_ADMIN_PASSWORD) {
    throw "AZURE_VM_ADMIN_PASSWORD is not available."
}

$securePassword = ConvertTo-SecureString $env:AZURE_VM_ADMIN_PASSWORD -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential(
    $env:AZURE_VM_ADMIN_USERNAME,
    $securePassword
)

Write-Output "Building VM configuration..."

$vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize

$vmConfig = Set-AzVMOperatingSystem `
    -VM $vmConfig `
    -Windows `
    -ComputerName $VMName `
    -Credential $credential `
    -ProvisionVMAgent `
    -EnableAutoUpdate:$EnableAutoUpdates

$vmConfig = Set-AzVMSourceImage `
    -VM $vmConfig `
    -PublisherName $ImagePublisher `
    -Offer $ImageOffer `
    -Skus $ImageSku `
    -Version $ImageVersion

# Create NIC with dynamic private IP (DHCP) and no public IP.
Write-Output "Creating network interface..."

$nicName = "$VMName-nic"

$nic = New-AzNetworkInterface `
    -Name $nicName `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -SubnetId $subnet.Id `
    -EnableAcceleratedNetworking:$EnableAcceleratedNetworking

Write-Output "NIC created: $nicName"

$vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id

$vmConfig = Set-AzVMOSDisk `
    -VM $vmConfig `
    -StorageAccountType $OSDiskType `
    -CreateOption FromImage

if ($EnableBootDiagnostics) {
    $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Enable
}

# Trusted Launch with Secure Boot and vTPM.
if ($SecurityType -eq "TrustedLaunch") {
    Write-Output "Configuring Trusted Launch..."

    $vmConfig.SecurityProfile = New-Object Microsoft.Azure.Management.Compute.Models.SecurityProfile
    $vmConfig.SecurityProfile.SecurityType = "TrustedLaunch"
    $vmConfig.SecurityProfile.UefiSettings = New-Object Microsoft.Azure.Management.Compute.Models.UefiSettings
    $vmConfig.SecurityProfile.UefiSettings.SecureBootEnabled = $SecureBoot
    $vmConfig.SecurityProfile.UefiSettings.VTpmEnabled = $VTPM
}

Write-Output "Creating Azure VM..."

New-AzVM `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -VM $vmConfig `
    -Verbose

Write-Output ""
Write-Output "=============================================="
Write-Output "VM CREATION COMPLETED"
Write-Output "=============================================="

$createdVM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName

Write-Output "VM Name : $($createdVM.Name)"
Write-Output "VM Size : $($createdVM.HardwareProfile.VmSize)"
Write-Output "Status  : $($createdVM.ProvisioningState)"
Write-Output "=============================================="
