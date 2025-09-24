output "resource_group_names" {
  description = "List of provisioned resource group names."
  value       = [for k, m in module.user_environment : m.resource_group_name]
}

output "vm_names" {
  description = "List of provisioned VM names."
  value       = [for k, m in module.user_environment : m.vm_name]
}

output "vnet_names" {
  description = "List of provisioned VNet names."
  value       = [for k, m in module.user_environment : m.vnet_name]
}

output "entra_user_principal_names" {
  description = "List of Entra user principal names (when manage_entra_users=true)."
  value       = var.manage_entra_users ? [for k, u in module.entra_users : u.user_principal_name] : []
}

output "entra_user_object_ids" {
  description = "List of Entra user object ids (when manage_entra_users=true)."
  value       = var.manage_entra_users ? [for k, u in module.entra_users : u.object_id] : []
}

output "region_assignment" {
  description = "Map of user index -> region (round-robin assignment)."
  value       = { for i in local.user_indices : i => local.user_location_map[i] }
}

output "region_distribution" {
  description = "Count of environments per region."
  value = { for r in var.locations : r => length([for i in local.user_indices : local.user_location_map[i] if local.user_location_map[i] == r]) }
}

