locals {
  user_indices      = range(1, var.n + 1)
  region_count      = length(var.locations)
  user_location_map = { for i in local.user_indices : i => var.locations[(i - 1) % local.region_count] }
}

# Optional Entra ID users (created when manage_entra_users=true)
module "entra_users" {
  source   = "./modules/entra_user"
  for_each = var.manage_entra_users ? { for i in local.user_indices : i => i } : {}

  user_index = each.value
  domain     = var.entra_user_domain
  password   = var.entra_user_password
}

module "user_environment" {
  source   = "./modules/user_environment"
  for_each = { for i in local.user_indices : i => i }

  user_index              = each.value
  location                = local.user_location_map[each.value]
  admin_username          = var.admin_username
  admin_password          = var.admin_password
  vm_size                 = var.vm_size
  assigned_user_object_id = var.manage_entra_users ? lookup(module.entra_users, tostring(each.value)).object_id : null
  create_role_assignment  = var.manage_entra_users
}

