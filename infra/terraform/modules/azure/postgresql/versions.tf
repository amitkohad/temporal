terraform {
  required_version = ">= 1.10.5, < 1.11.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.50.0"
    }
  }
}