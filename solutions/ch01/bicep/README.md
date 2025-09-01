# Azure SQL (Serverless) + Azure Container Registry Bicep Template

Deploys:

* Single Azure SQL Database (General Purpose serverless) with:
  * Auto-pause after 60 minutes of inactivity.
  * Autoscaling between 0.5 (implicit default) and 2 vCores.
  * Public network access enabled + single IPv4 firewall rule.
  * Globally unique logical server name derived from the resource group ID.
* Azure Container Registry (ACR) with configurable SKU (Basic default), unique name derived from resource group ID, public network access enabled, and admin user disabled (prefer Azure AD auth / managed identities).

## Files

* `main.bicep` - Core deployment template.
* `main.bicepparam` - Example parameter file (edit before use; never commit real secrets).

## Parameters

| Name | Description |
|------|-------------|
| appIpAddress | Public IPv4 address to whitelist (no CIDR). |
| administratorLogin | SQL admin login (cannot be changed later). |
| administratorLoginPassword | SQL admin password (secure parameter; avoid committing real secrets). |
| databaseName | Single database name (default: appdb). |
| maxVcores | Max vCores (capacity) for serverless (fixed to 2 here). |
| autoPauseDelayMinutes | Auto-pause delay (default 60). |
| acrSku | Container Registry SKU (`Basic`, `Standard`, `Premium`; default `Basic`). |

Minimum vCores (0.5) are implicit – `minCapacity` is omitted due to fractional literal limitation in Bicep; platform default for the selected SKU establishes 0.5 min vCores. If future Bicep versions allow decimals, add `minCapacity: 0.5` inside the database `properties` block to make it explicit.

## Deploy

Group deployment (replace values):

```pwsh
$rg = 'your-resource-group'
az deployment group create -g $rg -f main.bicep -p main.bicepparam
```

Or override inline without editing the param file:

```pwsh
az deployment group create -g $rg -f main.bicep \
  -p appIpAddress='40.112.10.25' administratorLogin='sqladminuser' \
  -p administratorLoginPassword='Your$ecureP@ss123' databaseName='appdb'

Recommended (avoid plaintext in param file history):

```pwsh
az deployment group create -g $rg -f main.bicep \
  -p appIpAddress=$env:APP_IP administratorLogin=$env:SQL_ADMIN \
  -p administratorLoginPassword=$env:SQL_ADMIN_PWD databaseName='appdb'
```

Where you set environment variables only in your current shell session:

```pwsh
$env:APP_IP='40.112.10.25'
$env:SQL_ADMIN='sqladminuser'
$env:SQL_ADMIN_PWD='Your$ecureP@ss123'
```
```

Outputs include:

* `sqlServerName`, `sqlServerFqdn`, `databaseNameOut`
* `containerRegistryName`, `containerRegistryLoginServer` (use for docker login / image tagging)

## Connection String Example

```
Server=tcp:<serverName>.database.windows.net,1433;Initial Catalog=appdb;Persist Security Info=False;User ID=sqladminuser;Password=<password>;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
```

## Notes

* SQL: Ensure your client retries initial connection attempts (serverless resume can take ~1 minute if paused).
* SQL: If you need to allow multiple IPs, add additional `firewallRules` resources or convert to parameters accepting arrays.
* ACR: Admin user is disabled; authenticate with `az acr login -n <registry>` when pushing images (requires Azure CLI login / RBAC permission).
* ACR: Upgrade SKU to `Standard` or `Premium` for higher throughput / features (geo-replication in Premium).
