variable "n" {
  type        = number
  default     = 5
  description = <<EOT
Number of user environments to provision.
Each environment consists of a resource group containing:
 - One Windows VM (developer workstation)
 - Public IP (for Bastion) and separate Public IP for NAT Gateway
 - NAT Gateway for outbound SNAT
 - Network Security Group
 - Virtual Network (derived CIDR 10.<index>.0.0/22)
 - Subnets: 'vms' plus 'AzureBastionSubnet'
Set to a reasonable small number for demos. Must be >=1.
EOT
}

variable "locations" {
  type        = list(string)
  description = <<EOT
List of Azure regions to distribute per-user environments across (round-robin).
Assignment rule: environment index i (1-based) is placed in
  locations[(i - 1) % length(locations)].
All regions must support the required resource types (VM size, Bastion, NAT Gateway).
Changing the region assigned to an existing index forces recreation of that environment's resource group and all contained resources.
Provide at least one region; empty list is invalid.
EOT
  validation {
    condition     = length(var.locations) > 0 && alltrue([for l in var.locations : length(trimspace(l)) > 0])
    error_message = "Provide at least one non-empty region name in locations."
  }
}

variable "admin_username" {
  type        = string
  default     = "azureuser"
  description = <<EOT
Administrative username configured on every Windows VM.
Avoid reserved names (Administrator, admin, etc.).
EOT
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = <<EOT
Administrative password for all Windows VMs.
Provide via CLI (-var or tfvars file) or environment variable TF_VAR_admin_password.
Do NOT commit real secrets to version control.
Password must satisfy Windows complexity requirements.
EOT
}

variable "vm_size" {
  type        = string
  default     = "Standard_D2as_v5"
  description = <<EOT
SKU/size of the Windows VM per user environment.
Should support required features (e.g. enough RAM/CPU for workshop tools).
EOT
}

variable "manage_entra_users" {
  type        = bool
  default     = true
  description = <<EOT
Flag controlling whether temporary Entra ID (Azure AD) user accounts are provisioned and granted Owner on each user resource group.
When true: an additional module creates n users and their object IDs are passed to each user_environment module which performs the RBAC assignment.
When false: no Entra users are created and no role assignments are added (user_environment skips RBAC if no user object id provided).
EOT
}

variable "entra_user_domain" {
  type        = string
  default     = ""
  description = <<EOT
Custom domain (e.g. example.onmicrosoft.com) to append to generated user UPNs (user<index>@domain). Required if manage_entra_users is true.
Leave empty to disable user creation implicitly or set manage_entra_users=false.
EOT
}

variable "entra_user_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = <<EOT
Password to assign to all provisioned Entra ID users (lab scenario). Provide via TF_VAR_entra_user_password env var.
If empty while manage_entra_users=true Terraform apply will fail in user module preconditions.
EOT
}

variable "subscription_id" {
  type        = string
  description = <<EOT
Azure Subscription ID where all resources will be deployed.
Provide via tfvars file (e.g. config.auto.tfvars), CLI -var flag, or environment variable TF_VAR_subscription_id.
Externalizing this value avoids editing provider configuration when switching target subscriptions.
If omitted, provider authentication will attempt to infer a default subscription from the Azure CLI / Managed Identity context (not recommended for reproducible workshop setups).
EOT
}


