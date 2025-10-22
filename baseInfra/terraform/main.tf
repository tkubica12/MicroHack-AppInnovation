locals {
  user_indices      = range(1, var.n + 1)
  region_count      = length(var.locations)
  user_location_map = { for i in local.user_indices : i => var.locations[(i - 1) % local.region_count] }
}

# Register required Azure resource providers (optional, controlled by manage_sub_providers)
# Users may not have subscription-level permissions to register providers
# This ensures all necessary providers are registered before deploying resources
module "resource_providers" {
  source = "./modules/resource_provider_registration"
  count  = var.manage_sub_providers ? 1 : 0
}

# Optional Entra ID users (created when manage_entra_users=true)
module "entra_users" {
  source   = "./modules/entra_user"
  for_each = var.manage_entra_users ? { for i in local.user_indices : i => i } : {}

  user_index = each.value
  domain     = var.entra_user_domain
  password   = var.entra_user_password
}

# Optional Azure user environments (created when manage_azure_resources=true)
module "user_environment" {
  source   = "./modules/user_environment"
  for_each = var.manage_azure_resources ? { for i in local.user_indices : i => i } : {}

  user_index              = each.value
  location                = local.user_location_map[each.value]
  admin_username          = var.admin_username
  admin_password          = var.admin_password
  vm_size                 = var.vm_size
  assigned_user_object_id = var.manage_entra_users ? lookup(module.entra_users, tostring(each.value)).object_id : null
  create_role_assignment  = var.manage_entra_users

  # Ensure resource providers are registered before deploying resources (if enabled)
  depends_on = [module.resource_providers]
}

