# OAuth2 Proxy Namespace
# Hosts OAuth2 Proxy instances for services without built-in authentication
# Provides Azure AD SSO for Hubble UI and other unauthenticated services

resource "kubernetes_namespace" "oauth2_proxy" {
  metadata {
    name = "oauth2-proxy"

    labels = {
      name                                 = "oauth2-proxy"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }

  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}
