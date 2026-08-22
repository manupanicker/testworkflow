using './main.bicep'

param vmName = 'win2022-bicep-test'
param resourceGroupName = 'CITRIX_BUILD'
param location = 'eastus'
param vnetName = 'vnet-eastus-2'
param subnetName = 'snet-eastus-1'
param vmSize = 'Standard_D2as_v7'
param dnsServer = '172.16.0.4'
param adminUsername = 'azureuser'

@secure()
param adminPassword = readEnvironmentVariable('AZURE_VM_ADMIN_PASSWORD')
