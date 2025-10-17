resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project}-${var.location}-${var.environment}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  lifecycle {
    ignore_changes = [tags["Creator"]]
  }
}

# Node subnet - where AKS node VMs get their IPs
resource "azurerm_subnet" "nodes" {
  #checkov:skip=CKV2_AZURE_31:AKS manages network security for node subnet; NSG is not required as AKS applies its own security rules
  name                 = "snet-nodes-${var.project}-${var.location}-${var.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/22"] # 1019 usable IPs - supports ~1000 nodes
}

# Pod subnet - where pod IPs are allocated (separate from nodes)
resource "azurerm_subnet" "pods" {
  #checkov:skip=CKV2_AZURE_31:AKS manages network security for pod subnet; delegated subnet cannot have NSG as Cilium handles network policies
  name                 = "snet-pods-${var.project}-${var.location}-${var.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.16.0/20"] # 4091 usable IPs - supports ~80 nodes @ 50 pods each

  delegation {
    name = "aks-delegation"

    service_delegation {
      name = "Microsoft.ContainerService/managedClusters"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}
