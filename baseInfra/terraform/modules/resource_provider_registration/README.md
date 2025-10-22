# Resource Provider Registration Module

This module registers Azure resource providers required for application innovation, AI, containers, databases, and infrastructure workloads.

## Purpose

Users in workshop environments often don't have subscription-level permissions to register resource providers. This module ensures all necessary providers are registered before any resources are deployed.

## Behavior

- **On Apply**: Registers all specified resource providers in the subscription
- **On Destroy**: Does NOT unregister providers (intentional design choice)
- **Idempotent**: Safe to run multiple times; only registers if not already registered

## Lifecycle Management

The module is designed to **only ensure registration**, not manage the full lifecycle:

```hcl
lifecycle {
  prevent_destroy = false  # Allows destroy to complete
  ignore_changes = []      # But doesn't actually change anything on destroy
}
```

When you run `terraform destroy`, the registration resources will be removed from Terraform state, but the resource providers **remain registered** in Azure. This is intentional because:

1. Unregistering providers can break existing resources in the subscription
2. Registration is subscription-wide and should persist beyond individual deployments
3. There's no cost to having providers registered

## Registered Providers

The module adopts a **proactive registration strategy**, registering **~80 common Azure resource providers** upfront. This ensures users can deploy resources through any method (Terraform, Portal, CLI, ARM templates, etc.) without permission issues.

The module registers providers across all major Azure service categories including:
- Compute & Containers (VMs, AKS, Container Apps, etc.)
- Storage (Blob, Files, Data Lake, NetApp, etc.)
- Networking (VNet, CDN, Front Door, etc.)
- Databases (SQL, PostgreSQL, MySQL, Cosmos DB, etc.)
- AI & Analytics (Cognitive Services, Machine Learning, Databricks, Synapse, etc.)
- Integration & Messaging (Service Bus, Event Hub, Event Grid, Logic Apps, etc.)
- Monitoring & Operations (Monitor, Log Analytics, Advisor, Cost Management, etc.)
- Security & Identity (Key Vault, Managed Identity, Security Center, etc.)
- DevOps & Developer Tools (Dev Center, DevTest Labs, Load Testing, etc.)
- IoT & Edge (IoT Hub, IoT Central, Digital Twins, Azure Arc, etc.)
- Migration & Backup (Azure Migrate, Recovery Services, etc.)
- Specialized Services (Virtual Desktop, Automation, Quantum, Healthcare APIs, etc.)
- Third-Party Integrations (Elastic, Datadog, Confluent, etc.)

**For the complete list of providers**, see the `resource_providers` list in [`locals.tf`](./locals.tf).

## Usage

Add this module to your main Terraform configuration:

```hcl
module "resource_providers" {
  source = "./modules/resource_provider_registration"
}
```

The module requires no input variables - the provider list is pre-defined in `locals.tf`.

## Customization

To add or remove providers, edit the `resource_providers` list in `locals.tf`.

## Outputs

- `registered_providers`: List of all registered provider namespaces
- `registration_status`: Map showing the registration status of each provider

## Requirements

- Terraform >= 1.0
- azurerm provider >= 4.0
- Azure subscription with permissions to register resource providers

**Important**: The azurerm provider must be configured with `resource_provider_registrations = "none"` to prevent conflicts:

```hcl
provider "azurerm" {
  resource_provider_registrations = "none"
  features {}
}
```

This disables automatic provider registration by Terraform and gives you full control via this module.

## Notes

- Registration can take 1-2 minutes per provider
- No cost associated with registering providers
- Providers remain registered even after `terraform destroy`
- Safe to run in subscriptions where providers are already registered (idempotent)
