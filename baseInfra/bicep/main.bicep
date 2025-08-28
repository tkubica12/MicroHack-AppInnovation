// Main template: provisions n workshop environments (RG + Public IP each) using modules
// targetScope: subscription
targetScope = 'subscription'

@description('Number of user environments (resource group + public IP) to deploy.')
@minValue(1)
param n int = 5

@description('Azure location for all resource groups & resources.')
param location string = 'westeurope'

@description('Admin username for all user VMs.')
param adminUsername string = 'azureuser'

@description('Admin password for all user VMs (secure).')
@secure()
param adminPassword string

// Loop deploying one module per user index (1..n) so names are user001, user002, ...
module user 'userInfra.bicep' = [for i in range(1, n): {
  name: 'userInfra${padLeft(string(i), 3, '0')}'
  params: {
    userIndex: i
    location: location
  adminUsername: adminUsername
  adminPassword: adminPassword
  }
}]

@description('Summary of provisioned resource group names.')
output resourceGroups array = [for i in range(0, n): user[i].outputs.resourceGroupName]
output vmNames array = [for i in range(0, n): user[i].outputs.vmName]
