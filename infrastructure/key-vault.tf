resource "azurerm_key_vault" "main" {
  name                        = "kv-mgmt-${var.location}-${var.environment}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "premium"
  enabled_for_disk_encryption = true
  purge_protection_enabled    = true

  public_network_access_enabled = true

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"

    ip_rules = concat(
      [
        # Azure DevOps hosted runners CIDRs
        "13.107.6.0/24",
        "13.107.9.0/24",
        "13.107.42.0/24",
        "13.107.43.0/24",
        "150.171.22.0/24",
        "150.171.23.0/24",
        "150.171.73.0/24",
        "150.171.74.0/24",
        "150.171.75.0/24",
        "150.171.76.0/24",
    ], var.ip_range_whitelist)
  }
}

resource "azurerm_private_endpoint" "endpoint_key_vault" {
  name                = "pip-kv-${var.project}-${var.location}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "kv-private-connection"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
  }
}

resource "azurerm_key_vault_key" "key_disk_encryption" {
  name         = "key-disk-encryption"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA-HSM"
  key_size     = 2048

  depends_on = [
    azurerm_key_vault_access_policy.service_principal_access_policy
  ]

  key_opts = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  expiration_date = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [expiration_date]
  }
}
