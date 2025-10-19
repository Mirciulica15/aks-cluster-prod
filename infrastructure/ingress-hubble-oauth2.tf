# Hubble UI Ingress (via OAuth2 Proxy)
# Provides HTTPS access to Cilium Hubble UI with Azure AD authentication
# Uses OAuth2 Proxy as authentication layer since Hubble has no built-in auth

resource "kubernetes_ingress_v1" "hubble_ui_oauth2" {
  metadata {
    name      = "hubble-ui-oauth2"
    namespace = kubernetes_namespace.oauth2_proxy.metadata[0].name

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
      "nginx.ingress.kubernetes.io/limit-rps" = "50"

      # Buffer size increases to handle large OAuth2 cookies/headers
      # OAuth2 Proxy with Azure AD can generate large session cookies that exceed default limits
      "nginx.ingress.kubernetes.io/proxy-buffer-size"           = "16k"
      "nginx.ingress.kubernetes.io/proxy-buffers"               = "4 32k"
      "nginx.ingress.kubernetes.io/proxy-busy-buffers-size"     = "64k"
      "nginx.ingress.kubernetes.io/client-header-buffer-size"   = "16k"
      "nginx.ingress.kubernetes.io/large-client-header-buffers" = "4 32k"
    }
  }

  spec {
    ingress_class_name = "nginx"

    # TLS configuration
    tls {
      hosts = [
        "hubble.${azurerm_public_ip.ingress.ip_address}.nip.io"
      ]
      secret_name = "hubble-ui-oauth2-tls-cert"
    }

    # Routing rules
    rule {
      host = "hubble.${azurerm_public_ip.ingress.ip_address}.nip.io"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "oauth2-proxy-hubble"
              port {
                number = 4180
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
    helm_release.oauth2_proxy_hubble,
    azurerm_public_ip.ingress
  ]
}
