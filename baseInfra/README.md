# Base Infrastructure (teacher only)
This folder contains the facilitator-facing automation to provision per‑student Azure environments for the MicroHack App Innovation workshop using Terraform (azapi-based). The earlier Bicep option has been removed; Terraform is now the single source.

## What Gets Deployed (Per Student Index `NNN`)
- Resource Group `rg-userNNN`
- Public IP for Bastion `pip-userNNN`
- Public IP for NAT Gateway `pip-nat-userNNN`
- NAT Gateway `nat-userNNN` (attached to both subnets via outbound associations)
- Network Security Group `nsg-userNNN` (RDP 3389 allowed only from VirtualNetwork)
- Virtual Network `vnet-userNNN` (CIDR `10.<index>.0.0/22`)
	- Subnet `vms` (`10.<index>.0.0/24`)
	- Subnet `AzureBastionSubnet` (`10.<index>.1.0/26`)
- Network Interface `nic-userNNN`
- Azure Bastion Host `bastion-userNNN`
- Windows Server 2025 VM `vm-userNNN` (image: WindowsServer 2025 Datacenter Azure Edition)
	- Custom Script Extension executing facilitator scripts in `baseInfra/terraform/scripts/` (downloaded from repo)
	- System-assigned Managed Identity (granted Owner on its resource group)

Optional (if `manage_entra_users=true`):
- Entra ID user `userNNN@<entra_user_domain>` granted Owner on `rg-userNNN`.

All resources are created using `azapi_resource` to maintain explicit API/version control while authenticating through the `azurerm` provider.

## Directory Layout
```
baseInfra/
	README.md              (this file)
	terraform/             (Terraform root module)
		main.tf
		variables.tf
		outputs.tf
		config.auto.tfvars   (sample values – scrub secrets!)
		modules/
			user_environment/  (infra per user)
			entra_user/        (optional Entra user creation)
		scripts/             (VM provisioning scripts consumed by extension)
```

## Prerequisites
- Terraform >= 1.7
- Azure CLI authenticated (`az login`) OR environment-based service principal auth
- Permissions: Subscription Owner or sufficient rights to create RG, networking, Bastion, VMs, role assignments, and (optionally) Entra user creation (Directory Writer / User Administrator)
- (Optional Entra users) Provide domain + password that meet tenant policies

## Key Variables
| Variable | Purpose | Notes |
|----------|---------|-------|
| `n` | Number of student environments | >=1; each adds costs (Bastion + VM + NAT) |
| `location` | Azure region | Default set in variables file |
| `admin_username` | Local admin on all VMs | Avoid reserved names |
| `admin_password` | Local admin password | Provide securely (env var) |
| `vm_size` | VM SKU | Default `Standard_D2as_v5` (adjust for capacity) |
| `manage_entra_users` | Toggle creation of Entra users | true/false |
| `entra_user_domain` | UPN domain for generated users | Required if manage_entra_users=true |
| `entra_user_password` | Password for all generated users | Lab only; rotate/dispose |

## Minimal Setup (Facilitator)
```pwsh
cd baseInfra/terraform
# Authenticate (interactive or service principal)
az login
az account set -s <YOUR_SUBSCRIPTION_ID>

# Provide sensitive values via environment variables
$env:TF_VAR_admin_password = "<StrongPassword1!>"
$env:TF_VAR_entra_user_password = "<AnotherStrongPassword1!>"  # only if using Entra users

# (Optional) Adjust config.auto.tfvars or create local.auto.tfvars
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

### Example `config.auto.tfvars`
```hcl
n                  = 5
location           = "swedencentral"
admin_username     = "azureuser"
vm_size            = "Standard_D2as_v5"
manage_entra_users = true
entra_user_domain  = "example.onmicrosoft.com"
```
Provide passwords through environment variables (recommended) or a private `local.auto.tfvars` that is git‑ignored.

## Outputs
Run `terraform output` after apply:
| Output | Description |
|--------|-------------|
| `resource_group_names` | All RG names created |
| `vm_names` | All VM names |
| `vnet_names` | All VNets per user |
| `entra_user_principal_names` | UPNs (only if users created) |
| `entra_user_object_ids` | Object IDs (only if users created) |

Use these for scripting follow‑up tasks or audits.

## Scaling Up or Down
- Increase `n`: add new higher index user environments (additive).
- Decrease `n`: Terraform will plan to destroy higher index environments that no longer fall in the new range (confirm carefully in plan output).
- Changing `vm_size`: Recreates each VM (data loss unless you externalize state – acceptable for ephemeral labs).

## Entra User Provisioning Details
- Created only when `manage_entra_users=true`.
- Naming: `userNNN@<entra_user_domain>` (001-based zero padded).
- Each user gets Owner only on its own resource group (least privilege for lab simplification; can be downgraded to custom role if needed later).
- Users share a single password for simplicity; rotate after event or set `force_password_change` logic (currently disabled for speed—can be enabled in module if required).

## Accessing a Student VM
Use Azure Bastion (portal RDP) – NSG blocks direct public RDP.
1. Portal > Resource Group `rg-userNNN`
2. Open `bastion-userNNN` (or VM > Connect > Bastion)
3. Credentials: admin username & password you configured
4. The provisioning scripts install tooling & the sample app (shortcut on desktop if script provides it). If app not running, review extension status and rerun script manually.

## Updating Provisioning Scripts
Scripts are packaged via Custom Script Extension at deployment. To force a re-run:
- Taint the extension: `terraform taint azapi_resource.user_environment["<index>"].vm_setup` (adjust address) then apply, OR
- Modify a file hash (e.g., change content) so Terraform triggers replacement.

## Destroy / Cleanup
```pwsh
terraform destroy
```
Destroys all per‑user resource groups. Verify subscription and confirm prompt.

## Security Considerations
- Shared lab passwords: treat as disposable; rotate or disable accounts post-event.
- Bastion over public IP: Acceptable for short‑lived workshop; for hardened scenarios add Just‑In‑Time, IP restrictions, or Privileged Access controls.
- Managed Identity Owner: Provided for simplicity so scripts can provision additional nested Azure resources if needed. Reduce to a custom role for production-like exercises.
- No diagnostics/log forwarding included yet (deliberately omitted to keep cost & complexity low). Add via azapi if needed.
