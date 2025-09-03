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

@description('GitHub organization / user that hosts the repository used for OIDC federation.')
@minLength(1)
param githubOrg string = 'tkubica12'

@description('GitHub repository name used for OIDC federation.')
@minLength(1)
param githubRepo string = 'MicroHack-AppInnovation'

@description('Git reference (branch) to trust for OIDC tokens (refs/heads/<branch>).')
@minLength(1)
param githubBranch string = 'main'

@description('User-assigned managed identity name dedicated for GitHub Actions OIDC.')
@minLength(3)
param githubActionsIdentityName string = 'gh-actions-mi'

@description('Name of the Log Analytics workspace (for Application Insights).')
param logAnalyticsWorkspaceName string = 'la-${uniqueString(resourceGroup().id)}'

@description('Retention (days) for Log Analytics workspace.')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionInDays int = 30

@description('Name of the Application Insights component.')
param appInsightsName string = 'appi-${uniqueString(resourceGroup().id)}'

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
    // Inject OpenTelemetry + App Insights connection string
    // NOTE: Metrics not supported for Application Insights destination currently.
    appInsightsConfiguration: {
      connectionString: appInsights.properties.ConnectionString
    }
    openTelemetryConfiguration: {
      tracesConfiguration: {
        destinations: [ 'appInsights' ]
      }
      logsConfiguration: {
        destinations: [ 'appInsights' ]
      }
    }
  }
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge01'
  }
}

// Log Analytics workspace (for Application Insights). Only created if OTEL enabled.
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: resourceGroup().location
  properties: {
    retentionInDays: logAnalyticsRetentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge04'
  }
}

// Application Insights (workspace-based)
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: resourceGroup().location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    WorkspaceResourceId: logAnalytics.id
  }
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge04'
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
  activeRevisionsMode: 'Multiple'
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

// -----------------------------------------------------------------------------
// GitHub Actions Managed Identity (for CI/CD via OIDC)
// -----------------------------------------------------------------------------
resource ghActionsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: githubActionsIdentityName
  location: resourceGroup().location
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge03'
  }
}

// Federated identity credential allowing GitHub OIDC tokens from specific repo + branch
// Subject format: repo:<org>/<repo>:ref:refs/heads/<branch>
resource ghActionsFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2025-01-31-preview' = {
  name: 'github-actions'
  parent: ghActionsIdentity
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOrg}/${githubRepo}:ref:refs/heads/${githubBranch}'
    audiences: [ 'api://AzureADTokenExchange' ]
  }
}

// Additional federated credential for GitHub environment 'staging'
// Subject format for environments: repo:<org>/<repo>:environment:<environmentName>
resource ghActionsFederatedCredentialStaging 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2025-01-31-preview' = {
  name: 'github-actions-staging'
  parent: ghActionsIdentity
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOrg}/${githubRepo}:environment:staging'
    audiences: [ 'api://AzureADTokenExchange' ]
  }
  dependsOn: [
    ghActionsFederatedCredential
  ]
}

// Additional federated credential for GitHub environment 'production'
resource ghActionsFederatedCredentialProduction 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2025-01-31-preview' = {
  name: 'github-actions-production'
  parent: ghActionsIdentity
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOrg}/${githubRepo}:environment:production'
    audiences: [ 'api://AzureADTokenExchange' ]
  }
  dependsOn: [
    ghActionsFederatedCredentialStaging
  ]
}

// Contributor role assignment for the GitHub Actions identity at resource group scope
resource ghActionsContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, ghActionsIdentity.id, 'Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: ghActionsIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    ghActionsFederatedCredential
    ghActionsFederatedCredentialStaging
    ghActionsFederatedCredentialProduction
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
output ghActionsIdentityClientId string = ghActionsIdentity.properties.clientId
output ghActionsIdentityPrincipalId string = ghActionsIdentity.properties.principalId
output ghActionsIdentityResourceId string = ghActionsIdentity.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsNameOut string = appInsights.name
output logAnalyticsWorkspaceNameOut string = logAnalytics.name
