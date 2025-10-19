output "client_certificate" {
  value     = azurerm_kubernetes_cluster.main.kube_config[0].client_certificate
  sensitive = true
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive = true
}

# Ingress outputs
output "ingress_public_ip" {
  value       = azurerm_public_ip.ingress.ip_address
  description = "Public IP address of the ingress controller"
}

output "grafana_url" {
  value       = "https://grafana.${azurerm_public_ip.ingress.ip_address}.nip.io"
  description = "URL to access Grafana dashboards"
}

output "argocd_url" {
  value       = "https://argocd.${azurerm_public_ip.ingress.ip_address}.nip.io"
  description = "URL to access Argo CD UI"
}

output "hubble_url" {
  value       = "https://hubble.${azurerm_public_ip.ingress.ip_address}.nip.io"
  description = "URL to access Hubble UI (Azure AD authentication via OAuth2 Proxy)"
}
