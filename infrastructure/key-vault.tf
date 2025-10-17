resource "azurerm_key_vault" "main" {
  #checkov:skip=CKV2_AZURE_32:Intentionally using public endpoint with IP whitelist instead of private endpoint to avoid additional networking costs
  name                        = "kv-mgmt-${var.location}-${var.environment}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "premium"
  enabled_for_disk_encryption = true
  purge_protection_enabled    = true
  rbac_authorization_enabled  = true

  public_network_access_enabled = true

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.ip_range_whitelist
  }

  lifecycle {
    ignore_changes = [tags["Creator"]]
  }
}

resource "azurerm_role_assignment" "self_uaa" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "User Access Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "terraform_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [azurerm_role_assignment.self_uaa]
}

resource "azurerm_key_vault_key" "key_disk_encryption" {
  name         = "key-disk-encryption"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA-HSM"
  key_size     = 2048

  depends_on = [azurerm_role_assignment.terraform_kv_admin]

  key_opts = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]

  expiration_date = timeadd(timestamp(), "8760h")

  lifecycle {
    ignore_changes = [tags["Creator"], expiration_date]
  }
}
