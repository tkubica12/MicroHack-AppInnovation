# Bastion Host
resource "azapi_resource" "bastion" {
  type      = "Microsoft.Network/bastionHosts@2023-04-01"
  name      = local.bastion_name
  location  = var.location
  parent_id = azapi_resource.rg.id
  body = {
    sku = { name = "Basic" }
    properties = {
      ipConfigurations = [{
        name = "bastionIpConfig"
        properties = {
          subnet          = { id = "${azapi_resource.vnet.id}/subnets/${local.bastion_subnet_name}" }
          publicIPAddress = { id = azapi_resource.public_ip.id }
        }
      }]
    }
  }
  depends_on = [azapi_resource.vnet, azapi_resource.public_ip]
}
