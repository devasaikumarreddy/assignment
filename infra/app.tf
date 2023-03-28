locals {
  aks_cluster_name    = "aks-${local.app_name}-${var.env}"
  location            = "westeurope"
  app_name            = var.appName
  resource_group_name = "rg-${local.app_name}-${var.env}"
  //inf_resource_group_name = "rg-inf-${var.env}"
  log_analytics_workspacename = "logs-${local.app_name}-${var.env}"
  vnet_name = "vnet-${local.app_name}-${var.env}"
  acr_name = "acr${local.app_name}${var.env}"
  key_vault_name = "kv-${local.app_name}-${var.env}"
  default_tags = {
    environment = var.env
    }

}


resource "azurerm_resource_group" "rg" {
  location = local.location
  name     = local.resource_group_name
  tags = local.default_tags
}


resource "azurerm_management_lock" "rglock" {
  name       = local.resource_group_name
  scope      = azurerm_resource_group.rg.id
  lock_level = "CanNotDelete"
  notes      = "This Resource Group is not supposed to delete"
}

# resource "azurerm_resource_group" "infrg" {
#   location = local.location
#   name     = local.inf_resource_group_name
#   tags = local.default_tags
# }


# resource "azurerm_management_lock" "infrglock" {
#   name       = local.resource_group_name
#   scope      = azurerm_resource_group.infrg.id
#   lock_level = "CanNotDelete"
#   notes      = "This Resource Group is Read-Only"
# }


# resource "azurerm_virtual_network" "vnet" {
#     name                = local.vnet_name
#     location            = azurerm_resource_group.infrg.location
#     resource_group_name = azurerm_resource_group.infrg.name
#     address_space       = ["10.1.0.0/16"]

#       tags = local.default_tags

# }

# resource "azurerm_subnet" "aks-subnet1" {
#     name                 = "aks-subnet1"
#     resource_group_name  = azurerm_resource_group.infrg.name
#     virtual_network_name = azurerm_virtual_network.vnet.name
#     address_prefixes     = ["10.1.0.64/27"]
# }

# resource "azurerm_subnet" "aks-subnet2" {
#     name                 = "aks-subnet2"
#     resource_group_name  = azurerm_resource_group.infrg.name
#     virtual_network_name = azurerm_virtual_network.vnet.name
#     address_prefixes     = ["10.1.1.0/24"]
# }

resource "azurerm_log_analytics_workspace" "insights" {
  name                = local.log_analytics_workspacename
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  retention_in_days   = 30
  tags = local.default_tags

}

resource "azurerm_log_analytics_solution" "solution" {
  location              = azurerm_log_analytics_workspace.insights.location
  resource_group_name   = azurerm_resource_group.rg.name
  solution_name         = "ContainerInsights"
  workspace_name        = azurerm_log_analytics_workspace.insights.name
  workspace_resource_id = azurerm_log_analytics_workspace.insights.id

  plan {
    product   = "OMSGallery/ContainerInsights"
    publisher = "Microsoft"
  }
}

data "azurerm_client_config" "current" {}


resource "azurerm_key_vault" "keyvault" {
  name                        = local.key_vault_name
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get","Set","List"
    ]

    storage_permissions = [
      "Get"
    ]
  }
}

resource "azurerm_container_registry" "acr" {
  name                = "${local.acr_name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
  tags = local.default_tags
}

# data "azuread_client_config" "current" {}

# resource "azuread_group" "aks_administrators" {
#   display_name = "${local.aks_cluster_name}-administrators"
#   security_enabled = true
#   description = "Kubernetes administrators for the ${local.aks_cluster_name} cluster."
#   owners           = [data.azuread_client_config.current.object_id]
# }

data "azurerm_kubernetes_service_versions" "current" {
  location = azurerm_resource_group.rg.location
}

resource "azurerm_kubernetes_cluster" "aks" {
  dns_prefix          = local.aks_cluster_name
  kubernetes_version  = data.azurerm_kubernetes_service_versions.current.latest_version
  location            = azurerm_resource_group.rg.location
  name                = local.aks_cluster_name
  node_resource_group = "${azurerm_resource_group.rg.name}-aks"
  resource_group_name = azurerm_resource_group.rg.name
  tags = local.default_tags

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.insights.id
    
  }

  network_profile {
    network_plugin = "kubenet"
    
  }


  default_node_pool {
    enable_auto_scaling  = true
    max_count            = 3
    min_count            = 1
    node_count           = 1
    name                 = "system"
    orchestrator_version = data.azurerm_kubernetes_service_versions.current.latest_version
    os_disk_size_gb      = 1024
    vm_size              = "Standard_DS2_v2"
    type                 = "VirtualMachineScaleSets"
    //vnet_subnet_id       = azurerm_virtual_network.vnet.id
  }
  
  identity { type = "SystemAssigned" }

}

resource "azurerm_key_vault_secret" "kvsecretaks" {
  name         = "aks-admin-kubeconfig-raw"
  value        = azurerm_kubernetes_cluster.aks.kube_admin_config_raw
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "azurerm_key_vault_secret" "kvsecretaks1" {
  name         = "aks-kubeconfig-raw"
  value        = azurerm_kubernetes_cluster.aks.kube_config_raw
  key_vault_id = azurerm_key_vault.keyvault.id
}

# Create Role Assignment on Azure Container Registry
resource "azurerm_role_assignment" "aks_role_assignment" {
  principal_id                     =  azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}