variable "user_index" {
  type        = number
  description = <<EOT
Zero-based numeric index (1..n in root loop) used to derive:
 - Naming (rg-userNNN, vm-userNNN, etc.)
 - Address space segments (10.<index>.0.0/22)
Must align with the range passed from root module.
EOT
}

variable "location" {
  type        = string
  description = <<EOT
Azure region where all resources for this per-user environment are created.
Should match root `location` for consistency.
EOT
}

variable "admin_username" {
  type        = string
  description = <<EOT
Local administrator account name configured on the Windows VM.
Avoid reserved names (Administrator, admin) to prevent provisioning errors.
EOT
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = <<EOT
Local administrator password for the Windows VM.
Inherited from root; provided once for all environments.
Meets Windows complexity rules; not logged due to `sensitive=true`.
EOT
}

variable "vm_size" {
  type        = string
  description = <<EOT
Azure compute SKU (e.g. Standard_D2as_v5) applied to the VM.
Changing after initial apply will force VM recreation.
EOT
}

variable "assigned_user_object_id" {
  type        = string
  default     = null
  description = <<EOT
Optional Entra ID user object ID to receive Owner role on this resource group.
If null, no role assignment resource is created (labs without managed users).
Supplied by root when `manage_entra_users=true`.
EOT
}

variable "create_role_assignment" {
  type        = bool
  default     = false
  description = <<EOT
Explicit switch controlling creation of the Owner role assignment.
Set true only when an assigned_user_object_id is also provided.
Decoupling the boolean avoids unknown value propagation issues in count.
EOT
}
