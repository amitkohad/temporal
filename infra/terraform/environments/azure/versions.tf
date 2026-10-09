terraform {
  required_version = ">= 1.10.5, < 1.11.0"
  // Activate the private backend only after the runner route and migration are verified.
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.50.0"
    }
  }
}
