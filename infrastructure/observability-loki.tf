# Grafana Loki - Log Aggregation System
# Scalable log aggregation with label-based indexing
# Includes Promtail DaemonSet for log collection from nodes

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.16.0" # Latest stable
  namespace  = kubernetes_namespace.observability.metadata[0].name

  values = [
    yamlencode({
      # Deployment mode (single binary for simplicity, can scale to distributed later)
      deploymentMode = "SingleBinary"

      loki = {
        # Authentication (disabled for internal cluster)
        auth_enabled = false

        # Storage configuration
        commonConfig = {
          replication_factor = 1
        }

        storage = {
          type = "filesystem"
          filesystem = {
            chunks_directory = "/var/loki/chunks"
            rules_directory  = "/var/loki/rules"
          }
        }

        # Schema configuration
        schemaConfig = {
          configs = [
            {
              from         = "2024-01-01"
              store        = "tsdb"
              object_store = "filesystem"
              schema       = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }

        # Limits configuration
        limits_config = {
          retention_period        = "744h" # 31 days
          max_query_series        = 100000
          max_query_parallelism   = 32
          ingestion_rate_mb       = 10
          ingestion_burst_size_mb = 20
        }
      }

      # Single binary configuration
      singleBinary = {
        replicas = 1

        persistence = {
          enabled      = true
          size         = "50Gi"
          storageClass = null # Use default storage class
        }

        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
        }
      }

      # Gateway (query frontend)
      gateway = {
        enabled  = true
        replicas = 1
      }

      # Disable components not needed in single binary mode
      backend = {
        replicas = 0
      }
      read = {
        replicas = 0
      }
      write = {
        replicas = 0
      }

      # Monitoring
      monitoring = {
        serviceMonitor = {
          enabled = true
        }
        selfMonitoring = {
          enabled = false
        }
        lokiCanary = {
          enabled = false
        }
      }

      # Test pod
      test = {
        enabled = false
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.observability,
    helm_release.kube_prometheus_stack
  ]
}

# Promtail DaemonSet - Collects logs from Kubernetes nodes
resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.16.0" # Match Loki version
  namespace  = kubernetes_namespace.observability.metadata[0].name

  set {
    name  = "config.clients[0].url"
    value = "http://loki-gateway.observability.svc.cluster.local/loki/api/v1/push"
  }

  depends_on = [
    kubernetes_namespace.observability,
    helm_release.loki
  ]
}

# Output Loki endpoints
output "loki_gateway_url" {
  description = "Loki gateway URL for log queries"
  value       = "http://loki-gateway.observability.svc.cluster.local"
}

output "loki_push_url" {
  description = "Loki push URL for log ingestion"
  value       = "http://loki-gateway.observability.svc.cluster.local/loki/api/v1/push"
}
