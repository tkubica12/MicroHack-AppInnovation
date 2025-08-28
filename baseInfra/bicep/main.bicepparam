using './main.bicep'

// Number of user environments (RG + networking + VM each)
param n = 1

// Azure region for all resource groups and contained resources
param location = 'swedencentral'

// Admin username for all Windows VMs
param adminUsername = 'azureuser'

// IMPORTANT: Replace with secure value or leverage Key Vault at deployment time.
// For local testing ONLY. Do not commit real credentials.
param adminPassword = 'Azure12345678'
