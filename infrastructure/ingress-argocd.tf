# Argo CD Ingress
# Provides HTTPS access to Argo CD UI with automatic TLS certificate
# Note: Argo CD has special requirements for gRPC and WebSocket connections
#
# IMPORTANT: Before applying this, ensure ClusterIssuers are created:
#   kubectl apply -f ../examples/clusterissuer-letsencrypt.yaml

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = kubernetes_namespace.argocd.metadata[0].name

    annotations = {
      # NGINX Ingress Controller annotations
      "kubernetes.io/ingress.class"                    = "nginx"
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "true"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"

      # cert-manager annotations for automatic certificate provisioning
      "cert-manager.io/cluster-issuer" = "letsencrypt-production"

      # Argo CD specific annotations for gRPC and WebSocket support
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
      "nginx.ingress.kubernetes.io/ssl-passthrough"  = "false"

      # Increase timeout for long-running operations
      "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "300"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "300"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "300"

      # Body size for large manifests
      "nginx.ingress.kubernetes.io/proxy-body-size" = "100m"

      # Rate limiting (optional)
      "nginx.ingress.kubernetes.io/limit-rps" = "100"
    }
  }

  spec {
    ingress_class_name = "nginx"

    # TLS configuration
    tls {
      hosts = [
        "argocd.${azurerm_public_ip.ingress.ip_address}.nip.io"
      ]
      secret_name = "argocd-tls-cert"
    }

    # Routing rules
    rule {
      host = "argocd.${azurerm_public_ip.ingress.ip_address}.nip.io"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.nginx_ingress,
    helm_release.cert_manager,
    helm_release.argocd,
    azurerm_public_ip.ingress
  ]
}
