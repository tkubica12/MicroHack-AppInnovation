using 'main.bicep'

// Example parameter values. Copy & adjust as needed.
param appIpAddress = '4.223.142.135'
param administratorLogin = 'sqladminuser'
// Provide a secure password at deployment time via CLI override or parameter file substitution.
param administratorLoginPassword = 'Azure12345678'
param databaseName = 'LegoCatalog'
param maxVcores = 2
param autoPauseDelayMinutes = 60
param acrSku = 'Basic'
// Optionally override generated registry name (must be globally unique, 5-50 alphanumeric)
// param acrName = 'mycustomacr12345'
