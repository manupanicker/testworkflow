@description('Azure VM name')
param vmName string

@description('Resource group containing the VM')
param resourceGroupName string = 'CITRIX_BUILD'

@description('Azure region')
param location string = 'eastus'

@description('Existing VNet name')
param vnetName string = 'vnet-eastus-2'

@description('Existing subnet name')
param subnetName string = 'snet-eastus-1'

@description('VM size')
param vmSize string = 'Standard_D2as_v7'

@description('DNS server used by the NIC')
param dnsServer string = '172.16.0.4'

@description('Windows administrator username')
param adminUsername string = 'azureuser'

@secure()
@description('Windows administrator password')
param adminPassword string

@description('Windows Server image publisher')
param imagePublisher string = 'microsoftwindowsserver'

@description('Windows Server image offer')
param imageOffer string = 'windowsserver2022'

@description('Windows Server image SKU')
param imageSku string = '2022-datacenter-smalldisk-g2'

@description('Windows Server image version')
param imageVersion string = 'latest'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(resourceGroupName)
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: subnetName
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    enableAcceleratedNetworking: true
    dnsSettings: {
      dnsServers: [
        dnsServer
      ]
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnet.id
          }
          primary: true
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: imageVersion
      }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
          enableHotpatching: false
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

output vmName string = vm.name
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output nicId string = nic.id
