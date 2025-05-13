resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project}-${var.location}-${var.environment}"
  location = var.location

  lifecycle {
    ignore_changes = [tags["Creator"]]
  }
}
