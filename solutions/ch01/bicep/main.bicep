// Azure SQL Database (serverless) deployment template
// Requirements implemented:
// - Serverless Azure SQL single database (General Purpose tier) with auto-pause after 60 minutes
// - Autoscaling between 0.5 (default min) and 2 vCores (capacity = 2)
// - Public network access enabled and application IP whitelisted via firewall rule
// - Administrator login & password as parameters (secure for password)
// - Location derived from resource group
// - Globally unique server name using uniqueString(resourceGroup().id)

@description('Public IPv4 address of the application or developer machine to whitelist (e.g. 40.112.10.25). Do not include CIDR suffix.')
param appIpAddress string

@description('SQL Server administrator login name (cannot be changed later).')
@minLength(1)
param administratorLogin string

@description('SQL Server administrator login password.')
@secure()
param administratorLoginPassword string

@description('Name of the single database to create.')
@minLength(1)
param databaseName string = 'appdb'

@description('Maximum vCores for the serverless database (capacity). Requirement specifies 2.')
@allowed([ 2 ])
param maxVcores int = 2

@description('Auto-pause delay in minutes. Requirement: 60 (1 hour).')
@minValue(15)
param autoPauseDelayMinutes int = 60

// NOTE: Minimum capacity (0.5 vCores) is not explicitly parameterized because Bicep currently only supports integer numeric literals.
// The platform default for serverless with max <= 4 vCores sets min vCores to 0.5 automatically. This satisfies requirement (0.5 - 2).
// If later adjustment is needed when fractional literals become supported, add: properties.minCapacity = 0.5

var serverName = 'sql${uniqueString(resourceGroup().id)}'
var skuName = 'GP_S_Gen5_${maxVcores}' // Serverless General Purpose Gen5 with provided max capacity

// Logical SQL Server
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
    'workload': 'challenge01'
  }
}

// Firewall rule to allow the application / developer IP (single address)
resource appIpFirewall 'Microsoft.Sql/servers/firewallRules@2024-11-01-preview' = {
  name: 'AllowAppIp'
  parent: sqlServer
  properties: {
    startIpAddress: appIpAddress
    endIpAddress: appIpAddress
  }
}

// Single serverless database
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
    // minCapacity intentionally omitted (see note above) -> defaults to 0.5 for this max capacity
  }
  tags: {
    'managed-by': 'bicep'
    workload: 'challenge01'
  }
}

output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseNameOut string = database.name
