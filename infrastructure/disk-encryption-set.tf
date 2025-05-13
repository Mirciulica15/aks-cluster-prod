resource "azurerm_disk_encryption_set" "main" {
  name                = "des-${var.project}-${var.location}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  key_vault_key_id    = azurerm_key_vault_key.key_disk_encryption.versionless_id

  auto_key_rotation_enabled = true

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_key_vault_access_policy" "disk_access_policy" {
  key_vault_id = azurerm_key_vault.main.id

  tenant_id = azurerm_disk_encryption_set.main.identity[0].tenant_id
  object_id = azurerm_disk_encryption_set.main.identity[0].principal_id

  key_permissions = ["Create", "Delete", "Get", "Purge", "Recover", "Update", "List", "Decrypt", "Sign", "WrapKey", "UnwrapKey"]
}

resource "azurerm_key_vault_access_policy" "service_principal_access_policy" {
  key_vault_id = azurerm_key_vault.main.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

  key_permissions = ["Create", "Delete", "Get", "Purge", "Recover", "Update", "List", "Decrypt", "Sign", "GetRotationPolicy", "WrapKey", "UnwrapKey"]
}
