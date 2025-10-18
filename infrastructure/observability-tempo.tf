# Grafana Tempo - Distributed Tracing Backend
# OTEL-native trace storage and query service
# Uses local storage (can be upgraded to S3/Azure Blob later)

resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.10.0" # Latest stable
  namespace  = kubernetes_namespace.observability.metadata[0].name

  values = [
    yamlencode({
      # Tempo configuration
      tempo = {
        # Storage configuration (local for now, upgrade to object storage later)
        storage = {
          trace = {
            backend = "local"
            local = {
              path = "/var/tempo/traces"
            }
          }
        }

        # Receiver configuration (OTLP support)
        receivers = {
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:4317"
              }
              http = {
                endpoint = "0.0.0.0:4318"
              }
            }
          }
          jaeger = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:14250"
              }
              thrift_http = {
                endpoint = "0.0.0.0:14268"
              }
            }
          }
          zipkin = {
            endpoint = "0.0.0.0:9411"
          }
        }

        # Retention configuration
        retention = "720h" # 30 days
      }

      # Persistence for traces
      persistence = {
        enabled     = true
        size        = "50Gi"
        accessModes = ["ReadWriteOnce"]
      }

      # Service configuration
      service = {
        type = "ClusterIP"
      }

      # Resources
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

      # Security context to allow writing to mounted volume
      securityContext = {
        fsGroup      = 10001
        runAsUser    = 10001
        runAsNonRoot = true
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.observability
  ]
}

# Output Tempo endpoint for OTEL Collector
output "tempo_otlp_grpc_endpoint" {
  description = "Tempo OTLP gRPC endpoint for trace ingestion"
  value       = "tempo.observability.svc.cluster.local:4317"
}

output "tempo_otlp_http_endpoint" {
  description = "Tempo OTLP HTTP endpoint for trace ingestion"
  value       = "http://tempo.observability.svc.cluster.local:4318"
}
