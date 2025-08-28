// workload.bicep: per-user resource group scoped resources (Public IP, NSG, VNet, NIC, VM, Bastion)
targetScope = 'resourceGroup'

@description('User index (1..n) used for zero-padded naming.')
param userIndex int
@description('Location for all resources.')
param location string
@description('Admin username for the Windows VM.')
param adminUsername string
@description('Admin password for the Windows VM.')
@secure()
param adminPassword string
@description('Optional explicit VNet CIDR; default derives 10.<userIndex>.0.0/22 to allow space for additional subnets.')
param vnetAddressSpace string = ''
@description('Optional explicit vms subnet CIDR; defaults to first /24 inside derived VNet.')
param subnetAddressPrefix string = ''
@description('VM size.')
param vmSize string = 'Standard_B2als_v2'
@description('Enable accelerated networking if size supports it.')
param enableAcceleratedNetworking bool = false

var padded = padLeft(string(userIndex), 3, '0')
var pipName = 'pip-user${padded}'
var vnetName = 'vnet-user${padded}'
var vmsSubnetName = 'vms'
var bastionSubnetName = 'AzureBastionSubnet'
var nsgName = 'nsg-user${padded}'
var nicName = 'nic-user${padded}'
var vmName = 'vm-user${padded}'

// Derived address space now /22 giving room for multiple /24 segments: 10.X.0.0 - 10.X.3.255
var derivedVnetCidr = '10.${userIndex}.0.0/22'
var vnetCidr = empty(vnetAddressSpace) ? derivedVnetCidr : vnetAddressSpace
var derivedVmsSubnetCidr = '10.${userIndex}.0.0/24'
var derivedBastionSubnetCidr = '10.${userIndex}.1.0/26'
var vmsSubnetCidr = empty(subnetAddressPrefix) ? derivedVmsSubnetCidr : subnetAddressPrefix

// Inlined Public IP (was previously a separate module pip.bicep). Bastion requires Standard SKU.
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: pipName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: nsgName
  location: location
  properties: {
    // Allow RDP only from within the virtual network (Bastion host resides in AzureBastionSubnet)
    securityRules: [
      {
        name: 'rdp-from-vnet'
        properties: {
          priority: 300
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3389'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetCidr ]
    }
    subnets: [
      {
        name: vmsSubnetName
        properties: {
          addressPrefix: vmsSubnetCidr
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: derivedBastionSubnetCidr
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, vmsSubnetName)
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
    enableAcceleratedNetworking: enableAcceleratedNetworking
  }
}

// Azure Bastion host using the created Standard Public IP
resource bastion 'Microsoft.Network/bastionHosts@2023-04-01' = {
  name: 'bastion-user${padded}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, bastionSubnetName)
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
  sku: {
    name: 'Basic'
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
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
  }
}

output publicIpName string = pipName
output vnetName string = vnetName
output vmName string = vmName
