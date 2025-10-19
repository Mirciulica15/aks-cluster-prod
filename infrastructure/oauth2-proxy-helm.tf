# OAuth2 Proxy Helm Chart
# Provides Azure AD authentication for services without built-in SSO
# Used for: Hubble UI and other internal tools

resource "helm_release" "oauth2_proxy_hubble" {
  name       = "oauth2-proxy-hubble"
  repository = "https://oauth2-proxy.github.io/manifests"
  chart      = "oauth2-proxy"
  version    = "7.8.0" # Latest stable as of 2025
  namespace  = kubernetes_namespace.oauth2_proxy.metadata[0].name

  timeout = 600

  values = [
    yamlencode({
      # Replica count
      replicaCount = 1

      # Resources
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }

      # OAuth2 Proxy configuration
      config = {
        # Azure AD provider
        provider = "azure"

        # Client ID and secret from Kubernetes secret
        clientID     = "" # Will be set via extraEnv
        clientSecret = "" # Will be set via extraEnv

        # Cookie settings
        cookieName     = "_oauth2_proxy_hubble"
        cookieSecret   = "" # Will be generated via extraEnv
        cookieSecure   = true
        cookieHttpOnly = true
        cookieSameSite = "lax"

        # Email domain restriction (optional)
        # emailDomains = ["accesa.eu"]
        emailDomains = ["*"] # Allow all domains for now

        # Upstream (backend service)
        upstreams = ["http://hubble-ui.kube-system.svc.cluster.local:80"]

        # Redirect URL
        redirectURL = "https://hubble.${azurerm_public_ip.ingress.ip_address}.nip.io/oauth2/callback"

        # Azure AD specific
        oidcIssuerURL = "https://login.microsoftonline.com/${var.azure_ad_tenant_id}/v2.0"
        scope         = "openid email" # Minimal scope to reduce cookie size

        # Session settings to minimize cookie size
        sessionCookieMinimal = true # Only store session ID in cookie, not full session data
      }

      # Extra environment variables from secret
      extraEnv = [
        {
          name  = "OAUTH2_PROXY_PROVIDER"
          value = "azure"
        },
        {
          name  = "OAUTH2_PROXY_AZURE_TENANT"
          value = var.azure_ad_tenant_id
        },
        {
          name = "OAUTH2_PROXY_CLIENT_ID"
          valueFrom = {
            secretKeyRef = {
              name = kubernetes_secret.oauth2_proxy_hubble.metadata[0].name
              key  = "client_id"
            }
          }
        },
        {
          name = "OAUTH2_PROXY_CLIENT_SECRET"
          valueFrom = {
            secretKeyRef = {
              name = kubernetes_secret.oauth2_proxy_hubble.metadata[0].name
              key  = "client_secret"
            }
          }
        },
        {
          name = "OAUTH2_PROXY_COOKIE_SECRET"
          valueFrom = {
            secretKeyRef = {
              name = kubernetes_secret.oauth2_proxy_hubble.metadata[0].name
              key  = "cookie_secret"
            }
          }
        },
        {
          name  = "OAUTH2_PROXY_OIDC_ISSUER_URL"
          value = "https://login.microsoftonline.com/${var.azure_ad_tenant_id}/v2.0"
        },
        {
          name  = "OAUTH2_PROXY_REDIRECT_URL"
          value = "https://hubble.${azurerm_public_ip.ingress.ip_address}.nip.io/oauth2/callback"
        },
        {
          name  = "OAUTH2_PROXY_UPSTREAMS"
          value = "http://hubble-ui.kube-system.svc.cluster.local:80"
        }
      ]

      # Service configuration
      service = {
        type       = "ClusterIP"
        portNumber = 4180
      }

      # Metrics for Prometheus
      metrics = {
        enabled = true
        servicemonitor = {
          enabled = true
          labels = {
            release = "kube-prometheus-stack"
          }
        }
      }

      # Security context
      securityContext = {
        runAsNonRoot = true
        runAsUser    = 2000
        fsGroup      = 2000
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.oauth2_proxy,
    kubernetes_secret.oauth2_proxy_hubble,
    helm_release.kube_prometheus_stack
  ]
}

# Azure AD OAuth secret for OAuth2 Proxy (Hubble)
resource "kubernetes_secret" "oauth2_proxy_hubble" {
  metadata {
    name      = "oauth2-proxy-hubble-secret"
    namespace = kubernetes_namespace.oauth2_proxy.metadata[0].name
  }

  data = {
    client_id     = var.oauth2_proxy_hubble_client_id
    client_secret = var.oauth2_proxy_hubble_client_secret
    cookie_secret = var.oauth2_proxy_cookie_secret
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace.oauth2_proxy
  ]
}
