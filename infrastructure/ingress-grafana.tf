# Grafana Ingress
# Provides HTTPS access to Grafana dashboards with automatic TLS certificate
#
# IMPORTANT: Before applying this, ensure ClusterIssuers are created:
#   kubectl apply -f ../examples/clusterissuer-letsencrypt.yaml

resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.observability.metadata[0].name

    annotations = {
      # NGINX Ingress Controller annotations
      "kubernetes.io/ingress.class"                    = "nginx"
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "true"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"

      # cert-manager annotations for automatic certificate provisioning
      "cert-manager.io/cluster-issuer" = "letsencrypt-production"

      # Backend protocol
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"

      # Rate limiting (optional)
      "nginx.ingress.kubernetes.io/limit-rps" = "100"
    }
  }

  spec {
    ingress_class_name = "nginx"

    # TLS configuration
    tls {
      hosts = [
        "grafana.${azurerm_public_ip.ingress.ip_address}.nip.io"
      ]
      secret_name = "grafana-tls-cert"
    }

    # Routing rules
    rule {
      host = "grafana.${azurerm_public_ip.ingress.ip_address}.nip.io"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "kube-prometheus-stack-grafana"
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
    helm_release.kube_prometheus_stack,
    azurerm_public_ip.ingress
  ]
}
