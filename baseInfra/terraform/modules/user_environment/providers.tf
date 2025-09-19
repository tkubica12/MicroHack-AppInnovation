terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = ">= 2"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4"
    }
  }
}

# Provider blocks are expected to be configured in the root module.
# This file simply declares the provider requirements for clarity and
# to support module reuse in isolation if ever extracted.
