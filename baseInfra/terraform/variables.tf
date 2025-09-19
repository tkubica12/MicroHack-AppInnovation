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

variable "location" {
  type        = string
  default     = "swedencentral"
  description = <<EOT
Azure region for all created resources.
Examples: westeurope, swedencentral, northeurope.
Changing this after creation forces replacement of all resources.
EOT
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


