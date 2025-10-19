# Ingress Namespace
# Hosts NGINX Ingress Controller and cert-manager for TLS certificate management

resource "kubernetes_namespace" "ingress" {
  metadata {
    name = "ingress-nginx"

    labels = {
      name                                 = "ingress-nginx"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }

  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"

    labels = {
      name                                 = "cert-manager"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }

  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}
