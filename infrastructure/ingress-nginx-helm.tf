# NGINX Ingress Controller
# Provides HTTP/HTTPS ingress with automatic TLS certificate management
# Uses static public IP with Azure DNS label for stable access

resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.11.3" # Latest stable as of 2025
  namespace  = kubernetes_namespace.ingress.metadata[0].name

  timeout = 600

  values = [
    yamlencode({
      controller = {
        # Replicas for high availability
        replicaCount = 2

        # Resource requests and limits
        resources = {
          requests = {
            cpu    = "100m"
            memory = "90Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        # Service configuration
        service = {
          type = "LoadBalancer"
          annotations = {
            # Use the static public IP we created
            "service.beta.kubernetes.io/azure-load-balancer-resource-group" = azurerm_kubernetes_cluster.main.node_resource_group
            # Azure automatically assigns the DNS label from the Public IP resource
          }
          loadBalancerIP        = azurerm_public_ip.ingress.ip_address
          externalTrafficPolicy = "Local" # Preserve source IP
        }

        # Metrics for Prometheus
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
            additionalLabels = {
              release = "kube-prometheus-stack"
            }
          }
        }

        # Pod placement (spread across nodes)
        affinity = {
          podAntiAffinity = {
            preferredDuringSchedulingIgnoredDuringExecution = [
              {
                weight = 100
                podAffinityTerm = {
                  labelSelector = {
                    matchExpressions = [
                      {
                        key      = "app.kubernetes.io/name"
                        operator = "In"
                        values   = ["ingress-nginx"]
                      }
                    ]
                  }
                  topologyKey = "kubernetes.io/hostname"
                }
              }
            ]
          }
        }

        # Security context
        podSecurityContext = {
          runAsNonRoot = true
          runAsUser    = 101
          fsGroup      = 101
        }

        # Additional configuration
        config = {
          # Security headers
          "use-forwarded-headers"      = "true"
          "compute-full-forwarded-for" = "true"
          "use-proxy-protocol"         = "false"

          # SSL configuration
          "ssl-protocols" = "TLSv1.2 TLSv1.3"
          "ssl-ciphers"   = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384"

          # Performance
          "keep-alive-requests"            = "100"
          "upstream-keepalive-connections" = "50"
        }

        # Admission webhooks (for validation)
        admissionWebhooks = {
          enabled = true
        }
      }

      # Default backend (optional 404 page)
      defaultBackend = {
        enabled = false
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.ingress,
    azurerm_public_ip.ingress,
    helm_release.kube_prometheus_stack # For ServiceMonitor
  ]
}
