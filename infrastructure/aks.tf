resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.project}-${var.location}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "management"
  # checkov:skip=CKV_AZURE_115: Intentionally not using private cluster to avoid the cost of setting up a Bastion VM or installing a VPN
  private_cluster_enabled   = false
  disk_encryption_set_id    = azurerm_disk_encryption_set.main.id
  automatic_upgrade_channel = "stable"
  azure_policy_enabled      = true
  local_account_disabled    = true
  # checkov:skip=CKV_AZURE_170: Intentionally using a free SKU to avoid costs
  sku_tier = "Free"

  api_server_access_profile {
    authorized_ip_ranges = var.ip_range_whitelist
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  # checkov:skip=CKV_AZURE_232: Intentionally using a single node pool for both system and user workloads to avoid costs
  default_node_pool {
    name                    = "npdefault"
    node_count              = 1
    vm_size                 = var.vm_size
    os_disk_type            = "Ephemeral"
    os_disk_size_gb         = 48
    max_pods                = 50
    host_encryption_enabled = true
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }
}
