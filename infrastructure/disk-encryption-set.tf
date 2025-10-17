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
    ignore_changes = [tags["Creator"]]
  }
}

# Grant Disk Encryption Set permissions via RBAC
resource "azurerm_role_assignment" "disk_kv_crypto_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_disk_encryption_set.main.identity[0].principal_id
}
