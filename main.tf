provider "azurerm" {
  version         = "=2.0.0"
  features {}
}

data "azurerm_storage_account" "tfstate" {
  resource_group_name = "hcpebld31143320zuya-WESTUS2"
  name                = "hcpebld31143320zuyawestu"
}

output "id" {
  value = data.azurerm_storage_account.tfstate.id
}

data "azurerm_key_vault_access_policy" "contributor" {
  name = "Key Management"
}

output "access_policy_key_permissions" {
  value = data.azurerm_key_vault_access_policy.contributor.key_permissions
}