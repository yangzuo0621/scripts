provider "azurerm" {
  alias = "registry"
  subscription_id = "8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8"
  version         = "=2.0.0"
  features {}
}

data "azurerm_container_registry" "prod" {
  provider = "azurerm.registry"
  name                = "hcpebld20200505zuyacr"
  resource_group_name = "hcpebld20200505zuya-westus2"
}

resource "local_file" "envrc-registry" {
  filename = "envrc-e2e-registry"

  # IDK why our name use is so very inconsistent
  sensitive_content = <<EOT
export REGISTRY=${data.azurerm_container_registry.prod.login_server}
export IMAGE_REGISTRY=${data.azurerm_container_registry.prod.login_server}


export REGISTRY_USERNAME=${data.azurerm_container_registry.prod.admin_username}
export REGISTRY_PASSWORD=${data.azurerm_container_registry.prod.admin_password}
export ImageRegistryUserName=${data.azurerm_container_registry.prod.admin_username}
export ImageRegistryPassword=${data.azurerm_container_registry.prod.admin_password}


export TUNNEL_REGISTRY=${data.azurerm_container_registry.prod.login_server}/
export TUNNEL_IMAGE_REGISTRY=${data.azurerm_container_registry.prod.login_server}
export TUNNEL_REGISTRY_USERNAME=${data.azurerm_container_registry.prod.admin_username}
export TUNNEL_REGISTRY_PASSWORD=${data.azurerm_container_registry.prod.admin_password}
EOT
}
