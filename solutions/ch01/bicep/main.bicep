@description('Public IPv4 address to whitelist (no CIDR).')
param appIpAddress string

@description('SQL administrator login name.')
@minLength(1)
param administratorLogin string

@description('SQL administrator login password.')
@secure()
param administratorLoginPassword string

@description('SQL database name.')
@minLength(1)
param databaseName string = 'appdb'

@description('Serverless database max vCores (capacity).')
@allowed([ 2 ])
param maxVcores int = 2

@description('Serverless database auto-pause delay (minutes).')
@minValue(15)
param autoPauseDelayMinutes int = 60

@description('DNS suffix for SQL server FQDN.')
param sqlServerDnsSuffix string = 'database.windows.net'

@description('Container Registry name (globally unique).')
@minLength(5)
@maxLength(50)
param acrName string = 'acr${uniqueString(resourceGroup().id)}'

@description('Container Registry SKU.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Basic'

@description('Container Apps managed environment name.')
param managedEnvName string = 'aca-env'

@description('Container App name.')
param containerAppName string = 'lego-catalog-app'

@description('Workload profile name (Consumption).')
param workloadProfileName string = 'consumption'

@description('User-assigned managed identity name for ACR pull.')
param userAssignedIdentityName string = 'aca-acr-mi'

@description('Storage account name for Azure Files.')
@minLength(3)
@maxLength(24)
param storageAccountName string = toLower('st${uniqueString(resourceGroup().id, 'files')}' )

@description('File share name for catalog seed JSON.')
@minLength(3)
param seedFileShareName string = 'catalogseed'

@description('File share name for images.')
@minLength(3)
param imagesFileShareName string = 'catalogimages'

// Variables
var serverName = 'sql${uniqueString(resourceGroup().id)}'
var skuName = 'GP_S_Gen5_${maxVcores}'
var sqlConnectionString = 'Server=tcp:${sqlServer.name}.${sqlServerDnsSuffix},1433;Initial Catalog=${database.name};Persist Security Info=False;User ID=${administratorLogin};Password=${administratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

// SQL logical server
resource sqlServer 'Microsoft.Sql/servers@2024-11-01-preview' = {
  name: serverName
  location: resourceGroup().location
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: '1.2'
  }
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge01'
  }
}

// SQL firewall rule (application IP)
resource appIpFirewall 'Microsoft.Sql/servers/firewallRules@2024-11-01-preview' = {
  name: 'AllowAppIp'
  parent: sqlServer
  properties: {
    startIpAddress: appIpAddress
    endIpAddress: appIpAddress
  }
}

// SQL firewall rule (allow Azure services 0.0.0.0)
resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2024-11-01-preview' = {
  name: 'AllowAzureServices'
  parent: sqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// SQL database (serverless)
resource database 'Microsoft.Sql/servers/databases@2024-11-01-preview' = {
  name: databaseName
  parent: sqlServer
  location: resourceGroup().location
  sku: {
    name: skuName
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: maxVcores
  }
  properties: {
    autoPauseDelay: autoPauseDelayMinutes
  }
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge01'
  }
}

// Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: resourceGroup().location
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge01'
  }
}

// Storage account (Azure Files)
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: resourceGroup().location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge01'
  }
}

// File share (seed JSON)
resource seedShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: '${storage.name}/default/${seedFileShareName}'
  properties: {
    enabledProtocols: 'SMB'
    shareQuota: 1
  }
}

// File share (images)
resource imagesShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: '${storage.name}/default/${imagesFileShareName}'
  properties: {
    enabledProtocols: 'SMB'
    shareQuota: 50
  }
}

// Container Apps managed environment
resource managedEnv 'Microsoft.App/managedEnvironments@2025-02-02-preview' = {
  name: managedEnvName
  location: resourceGroup().location
  properties: {
    workloadProfiles: [
      {
        name: workloadProfileName
        workloadProfileType: 'Consumption'
      }
    ]
  }
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge01'
  }
}

// Environment storage (seed share)
resource envStorageSeed 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  name: 'seedfiles'
  parent: managedEnv
  properties: {
    azureFile: {
      accountName: storage.name
      shareName: seedFileShareName
      accessMode: 'ReadWrite'
      accountKey: storage.listKeys().keys[0].value
    }
  }
}

// Environment storage (images share)
resource envStorageImages 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  name: 'imagefiles'
  parent: managedEnv
  properties: {
    azureFile: {
      accountName: storage.name
      shareName: imagesFileShareName
      accessMode: 'ReadWrite'
      accountKey: storage.listKeys().keys[0].value
    }
  }
}

// User-assigned managed identity
resource acrIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userAssignedIdentityName
  location: resourceGroup().location
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge01'
  }
}

// AcrPull role assignment (user-assigned identity)
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, acrIdentity.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: acrIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2025-02-02-preview' = {
  name: containerAppName
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acrIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: managedEnv.id
    workloadProfileName: workloadProfileName
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: acrIdentity.id
        }
      ]
      secrets: [
        {
          name: 'sql-conn'
          value: sqlConnectionString
        }
      ]
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          name: 'app'
          image: '${acr.properties.loginServer}/lego-catalog/app:latest'
          env: [
            {
              name: 'SQL_CONNECTION_STRING'
              secretRef: 'sql-conn'
            }
            {
              name: 'IMAGE_ROOT_PATH'
              value: '/mnt/images'
            }
            {
              name: 'SEED_DATA_PATH'
              value: '/mnt/seed/catalog.json'
            }
          ]
          resources: {
            cpu: 1
            memory: '2Gi'
          }
          volumeMounts: [
            {
              volumeName: 'seedvol'
              mountPath: '/mnt/seed'
            }
            {
              volumeName: 'imagesvol'
              mountPath: '/mnt/images'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
        rules: [
          {
            name: 'httpscale'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
      volumes: [
        {
          name: 'seedvol'
          storageName: envStorageSeed.name
          storageType: 'AzureFile'
        }
        {
          name: 'imagesvol'
          storageName: envStorageImages.name
          storageType: 'AzureFile'
        }
      ]
    }
  }
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge01'
  }
  dependsOn: [
    acrPullRole
  ]
}

// Outputs
output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseNameOut string = database.name
output containerRegistryName string = acr.name
output containerRegistryLoginServer string = acr.properties.loginServer
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output storageAccountNameOut string = storage.name
output seedFileShareNameOut string = seedFileShareName
output imagesFileShareNameOut string = imagesFileShareName
output acrIdentityResourceId string = acrIdentity.id
