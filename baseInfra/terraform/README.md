# Terraform (azapi) Workshop Infrastructure

This directory provides a Terraform implementation of the per-user workshop environment originally defined in Bicep. It intentionally uses the `azapi` provider for all Azure resources (instead of native `azurerm_*` resources) to give direct control over API versions and parity with the existing Bicep modules.

## Features

### Resource Provider Registration
Workshop users typically don't have subscription-level permissions to register Azure resource providers. This Terraform configuration automatically registers all required providers (AI, containers, databases, networking, etc.) before deploying any resources. 

**Important**: The provider configuration includes `resource_provider_registrations = "none"` to disable automatic provider registration by Terraform. This gives explicit control over which providers are registered via the `resource_provider_registration` module.

**Lifecycle**: Providers remain registered even after `terraform destroy` - this is intentional to avoid breaking existing resources in the subscription.

See `modules/resource_provider_registration/README.md` for the complete list of registered providers.

## Deployed Per User Environment
For each user index (1..n, zero‑padded) the module provisions:
- Resource Group `rg-userNNN`
- Standard Public IP for Azure Bastion `pip-userNNN`
- Standard Public IP for NAT Gateway `pip-nat-userNNN`
- NAT Gateway `nat-userNNN` associated to both subnets
- Network Security Group `nsg-userNNN` (RDP allowed only from VirtualNetwork)
- Virtual Network `vnet-userNNN` (default CIDR `10.<index>.0.0/22`)
  - Subnet `vms` (`10.<index>.0.0/24`)
  - Subnet `AzureBastionSubnet` (`10.<index>.1.0/26`)
- Network Interface `nic-userNNN`
- Azure Bastion Host `bastion-userNNN`
- Windows Server 2025 VM `vm-userNNN` (image: WindowsServer 2025 Datacenter Azure Edition)
  - System-assigned managed identity (Owner on its resource group)
- Custom Script Extension downloading and executing provisioning scripts from GitHub:
  - `setup.ps1` (orchestrator)
  - `SQL_install.ps1`, `App_install.ps1`, `Dev_install_initial.ps1`, `Dev_install_post_reboot.ps1`
  
Optional (when `manage_entra_users = true`):
- Entra ID user `userNNN@<entra_user_domain>` granted Owner on the matching resource group.

## Variables
Current input surface (deprecated override/acceleration flags removed for simplicity):

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `n` | number | yes | Number of per‑user environments (loop count). |
| `locations` | list(string) | yes | List of Azure regions. Per-user environments are assigned round-robin: index i -> `locations[(i-1) % len(locations)]`. |
| `admin_username` | string | yes | Local admin username for Windows VMs. |
| `admin_password` | string | yes | Local admin password (sensitive). Provide via env var or tfvars not committed. |
| `vm_size` | string | yes | VM size (e.g. `Standard_D2as_v5`). |
| `manage_entra_users` | bool | no (default true) | Whether to create lab Entra ID users and assign Owner role to each RG. |
| `entra_user_domain` | string | conditional | Domain used for generated user UPNs (required if manage_entra_users=true). |
| `entra_user_password` | string | conditional | Password for all generated users (required if manage_entra_users=true). |
| `manage_azure_resources` | bool | no (default true) | Whether to deploy Azure infrastructure resources. When false, only Entra ID users are created. |
| `manage_sub_providers` | bool | no (default true) | Whether to register Azure resource providers. Set to false if providers are already registered or you don't have subscription permissions. |

Implicit (no longer user configurable):
- VNet CIDR: `10.<index>.0.0/22`
- `vms` subnet: `10.<index>.0.0/24`
- `AzureBastionSubnet`: `10.<index>.1.0/26`
- Accelerated networking: always disabled (consistent behavior across chosen sizes).

### Entra ID User Provisioning
When enabled (`manage_entra_users=true`) a separate module creates one user per environment:
- UPN pattern: `userNNN@<entra_user_domain>` (NNN zero‑padded index)
- All users share the provided password (lab convenience only—do NOT use in production)
- Each user receives an Owner role assignment scoped only to its own resource group

Disable this by setting `manage_entra_users=false` (no users created, no RBAC performed).

### Region Distribution
Set one or multiple regions via `locations`. With two regions `["swedencentral","germanywestcentral"]` and `n=5`, assignment becomes:

| User Index | Region            |
|------------|-------------------|
| 1          | swedencentral     |
| 2          | germanywestcentral|
| 3          | swedencentral     |
| 4          | germanywestcentral|
| 5          | swedencentral     |

Differences in counts per region are at most 1 (round-robin fairness). Changing region assignments for existing indices forces recreation of those resource groups.

## Quick Start
```pwsh
# Initialize
terraform init

# Create your configuration file from the example
copy config.tfvars.example config.auto.tfvars

# Edit config.auto.tfvars with your specific values:
# - Set your subscription_id
# - Adjust n (number of environments)
# - Configure locations (Azure regions)
# - Set your entra_user_domain
# - Update admin_password and entra_user_password

# Apply (with increased parallelism for faster deployment)
terraform apply -parallelism=50

# Show outputs
terraform output
```

### Multiple Subscriptions with Workspaces
If you need to deploy to multiple subscriptions, use Terraform workspaces to manage separate state files:

```pwsh
# Create and switch to workspace for first subscription
terraform workspace new sub1
terraform apply -var-file="sub1.tfvars" -parallelism=50

# Create and switch to workspace for second subscription
terraform workspace new sub2  
terraform apply -var-file="sub2.tfvars" -parallelism=50

# List available workspaces
terraform workspace list

# Switch between workspaces
terraform workspace select sub1
terraform workspace select sub2

# Check current workspace
terraform workspace show
```

Each workspace maintains its own state file, allowing you to manage multiple deployments independently.

## Destroy
```pwsh
terraform destroy -parallelism=50
```
This removes all per-user resource groups (irreversible). Confirm before proceeding.

## Design Notes
- Every resource uses `azapi_resource` to honor the request of building an azapi-based configuration.
- The `azurerm` provider is still declared to simplify authentication (`data.azurerm_client_config.current`). No `azurerm_*` resources are created.
- Dependencies are expressed implicitly via ID references plus a few explicit `depends_on` where ordering is critical (e.g., NAT Gateway before NIC / VNet subnets association completeness, VM extension after VM).
- Naming exactly mirrors Bicep convention ensuring parity across tooling.
- The module keeps scripting logic unchanged—future improvements could parameterize script repository or pin commit SHAs for stronger immutability.

## Security & Secrets
- Never commit real `admin_password` values. Prefer environment variables or a secure secrets manager / pipeline variable group.
- Bastion restricts RDP by design (NSG rule only allows from VirtualNetwork). Access VMs through Azure Bastion (portal or CLI/SSH/RDP integration).

## Future Enhancements (Optional)
- Add diagnostics settings (Log Analytics) via azapi once monitoring requirements are finalized.
- Introduce per-user custom sizing or feature flags using `for_each` map input instead of simple range.
- Parameterize script source (branch/tag/commit) for reproducibility.

## Parity Validation Checklist
| Aspect | Bicep | Terraform (azapi) |
|--------|-------|-------------------|
| Naming | userNNN pattern | Same |
| Addressing | 10.<i>.0.0/22 derived | Same |
| Security | NSG RDP-from-vnet only | Same |
| Bastion | Basic SKU + Standard PIP | Same |
| Outbound | NAT Gateway + dedicated PIP | Same |
| Provisioning | Custom Script Extension | Same |
| VM Identity | Not originally highlighted | System-assigned identity + Owner on RG |

If you discover a divergence please open an issue or update this README with corrective steps.
