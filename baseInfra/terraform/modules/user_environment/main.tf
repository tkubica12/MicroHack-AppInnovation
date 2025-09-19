data "azurerm_client_config" "current" {}

# Resource Group only (other resources split across dedicated files)
resource "azapi_resource" "rg" {
  type      = "Microsoft.Resources/resourceGroups@2022-09-01"
  name      = local.rg_name
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  tags      = { SecurityControl = "ignore" }
  body      = {}
}

