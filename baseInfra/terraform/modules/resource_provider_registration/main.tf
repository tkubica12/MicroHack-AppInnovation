# Register all required resource providers
# This ensures providers are registered but does NOT unregister them on destroy
# This is intentional - resource providers should remain registered in the subscription
resource "azurerm_resource_provider_registration" "providers" {
  for_each = toset(local.resource_providers)

  name = each.value

  # Prevent Terraform from unregistering providers during destroy
  # Providers will remain registered in the subscription
  lifecycle {
    prevent_destroy = false
    ignore_changes = []
  }
}
