# Static Public IP for NGINX Ingress Controller
# Provides a stable IP address for accessing cluster services
# DNS: Using nip.io wildcard DNS service (e.g., grafana.<IP>.nip.io resolves to <IP>)
# Note: Azure DNS labels don't support wildcard subdomains, so we use nip.io instead

resource "azurerm_public_ip" "ingress" {
  name                = "pip-${var.project}-ingress-${var.location}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_kubernetes_cluster.main.node_resource_group # MC_ resource group
  allocation_method   = "Static"
  sku                 = "Standard"

  # Keep domain_name_label (Azure requires it once set, but we won't use it)
  # We use nip.io instead since Azure DNS doesn't support wildcard subdomains
  domain_name_label = "aks-mgmt-accesa-${var.environment}"

  tags = {
    Environment = var.environment
    Component   = "Ingress"
    Purpose     = "LoadBalancer for NGINX Ingress Controller"
  }

  lifecycle {
    ignore_changes = [
      tags["Creator"]
    ]
  }

  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}
