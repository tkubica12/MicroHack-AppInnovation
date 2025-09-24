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
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "azuread" {}

