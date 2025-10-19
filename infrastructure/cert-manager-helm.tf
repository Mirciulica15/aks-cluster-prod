# cert-manager
# Automated TLS certificate management for Kubernetes using Let's Encrypt
# Automatically provisions and renews certificates for Ingress resources

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.16.2" # Latest stable as of 2025
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  timeout = 600

  values = [
    yamlencode({
      # Install CRDs (CustomResourceDefinitions) with the chart
      installCRDs = true

      # Global configuration
      global = {
        leaderElection = {
          namespace = kubernetes_namespace.cert_manager.metadata[0].name
        }
      }

      # Controller configuration
      replicaCount = 1 # Single replica for cost optimization

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

      # Webhook configuration
      webhook = {
        replicaCount = 1

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
      }

      # CA Injector configuration
      cainjector = {
        replicaCount = 1

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
      }

      # Prometheus metrics
      prometheus = {
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
        runAsUser    = 1000
        fsGroup      = 1000
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.cert_manager,
    helm_release.kube_prometheus_stack # For ServiceMonitor
  ]
}
