resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project}-${var.location}-${var.environment}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-pes-${var.project}-${var.location}-${var.environment}"
  resource_group_name               = azurerm_resource_group.main.name
  virtual_network_name              = azurerm_virtual_network.main.name
  address_prefixes                  = ["10.0.0.0/24"]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-pes-${var.project}-${var.location}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}
