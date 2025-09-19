locals {
  padded                  = format("%03d", var.user_index)
  rg_name                 = "rg-user${local.padded}"
  pip_name                = "pip-user${local.padded}"
  nat_pip_name            = "pip-nat-user${local.padded}"
  vnet_name               = "vnet-user${local.padded}"
  vms_subnet_name         = "vms"
  bastion_subnet_name     = "AzureBastionSubnet"
  nsg_name                = "nsg-user${local.padded}"
  nic_name                = "nic-user${local.padded}"
  vm_name                 = "vm-user${local.padded}"
  nat_gateway_name        = "nat-user${local.padded}"
  bastion_name            = "bastion-user${local.padded}"
  derived_vnet_cidr       = "10.${var.user_index}.0.0/22"
  vnet_cidr               = local.derived_vnet_cidr
  derived_vms_subnet_cidr = "10.${var.user_index}.0.0/24"
  derived_bastion_cidr    = "10.${var.user_index}.1.0/26"
  vms_subnet_cidr         = local.derived_vms_subnet_cidr
  provisioning_scripts = [
    "https://github.com/tkubica12/MicroHack-AppInnovation/raw/refs/heads/main/baseInfra/scripts/setup.ps1",
    "https://github.com/tkubica12/MicroHack-AppInnovation/raw/refs/heads/main/baseInfra/scripts/SQL_install.ps1",
    "https://github.com/tkubica12/MicroHack-AppInnovation/raw/refs/heads/main/baseInfra/scripts/App_install.ps1",
    "https://github.com/tkubica12/MicroHack-AppInnovation/raw/refs/heads/main/baseInfra/scripts/Dev_install_initial.ps1",
    "https://github.com/tkubica12/MicroHack-AppInnovation/raw/refs/heads/main/baseInfra/scripts/Dev_install_post_reboot.ps1"
  ]
}
