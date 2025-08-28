// Module: Creates a resource group and a public IP inside it for one workshop user index
// targetScope: subscription
targetScope = 'subscription'

@description('Zero-padded (1..n) index of the user to provision (1 produces rg-user001 / pip-user001).')
param userIndex int

@description('Azure location for the resource group and contained resources.')
param location string = 'westeurope'

@description('Admin username for the Windows VM created for this user environment.')
param adminUsername string = 'azureuser'

@description('Admin password for the Windows VM (secure). Provide via parameter file or CLI secure parameter.')
@secure()
param adminPassword string

@description('Optional override of VNet address space (CIDR).')
param vnetAddressSpace string = ''

@description('Optional override of subnet address prefix (CIDR).')
param subnetAddressPrefix string = ''

var padded = padLeft(string(userIndex), 3, '0')
// Naming per CAF guidance: <resourceAbbrev>-user<###>
var rgName = 'rg-user${padded}'
// (Public IP name produced inside workload module)

// Create resource group for this user
resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: rgName
  location: location
}

// Delegate resource-group scoped infra to workload module
module workload 'workload.bicep' = {
  name: 'workload-user${padded}'
  scope: rg
  params: {
    userIndex: userIndex
    location: location
    adminUsername: adminUsername
    adminPassword: adminPassword
    vnetAddressSpace: vnetAddressSpace
    subnetAddressPrefix: subnetAddressPrefix
  }
}

@description('Name of the created resource group.')
output resourceGroupName string = rg.name

@description('Name of the created Public IP.')
output publicIpName string = workload.outputs.publicIpName

@description('Name of the created Virtual Network.')
output vnetName string = workload.outputs.vnetName

@description('Name of the created Virtual Machine.')
output vmName string = workload.outputs.vmName
