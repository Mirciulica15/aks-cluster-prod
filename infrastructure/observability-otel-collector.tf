# OpenTelemetry Collector - Centralized Telemetry Gateway
# Receives OTLP metrics, traces, and logs from applications
# Routes to Prometheus, Tempo, and Loki backends
# Deployment pattern (not DaemonSet) for application telemetry

resource "helm_release" "otel_collector" {
  name       = "opentelemetry-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = "0.104.0" # Latest stable
  namespace  = kubernetes_namespace.observability.metadata[0].name

  values = [
    yamlencode({
      # Image configuration (required in newer chart versions)
      # Use contrib image which includes all exporters (prometheusremotewrite, loki, etc.)
      image = {
        repository = "otel/opentelemetry-collector-contrib"
      }

      # Deployment mode (gateway/deployment pattern)
      mode = "deployment"

      # Replicas for HA
      replicaCount = 3

      # OpenTelemetry Collector configuration
      config = {
        # Receivers - Accept telemetry from applications
        receivers = {
          # OTLP receiver (gRPC and HTTP)
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

          # Prometheus receiver (scrape metrics)
          prometheus = {
            config = {
              scrape_configs = [
                {
                  job_name        = "otel-collector"
                  scrape_interval = "30s"
                  static_configs = [
                    {
                      targets = ["localhost:8888"]
                    }
                  ]
                }
              ]
            }
          }
        }

        # Processors - Transform and enrich telemetry
        processors = {
          # Batch processor (improves performance)
          batch = {
            timeout         = "10s"
            send_batch_size = 1024
          }

          # Memory limiter (prevents OOM)
          memory_limiter = {
            check_interval  = "1s"
            limit_mib       = 512
            spike_limit_mib = 128
          }

          # Kubernetes attributes processor (adds namespace, pod, etc.)
          k8sattributes = {
            auth_type   = "serviceAccount"
            passthrough = false
            extract = {
              metadata = [
                "k8s.namespace.name",
                "k8s.pod.name",
                "k8s.pod.uid",
                "k8s.deployment.name",
                "k8s.node.name"
              ]
              labels = [
                {
                  tag_name = "app.label.component"
                  key      = "app.kubernetes.io/component"
                  from     = "pod"
                }
              ]
            }
            pod_association = [
              {
                sources = [
                  {
                    from = "resource_attribute"
                    name = "k8s.pod.ip"
                  }
                ]
              },
              {
                sources = [
                  {
                    from = "resource_attribute"
                    name = "k8s.pod.uid"
                  }
                ]
              },
              {
                sources = [
                  {
                    from = "connection"
                  }
                ]
              }
            ]
          }

          # Resource detection (cloud provider, host)
          resourcedetection = {
            detectors = ["env", "system", "azure"]
            timeout   = "5s"
          }

          # Attributes processor (add cluster name)
          attributes = {
            actions = [
              {
                key    = "cluster"
                value  = "aks-management-northeurope-prod"
                action = "upsert"
              }
            ]
          }
        }

        # Exporters - Send telemetry to backends
        exporters = {
          # Prometheus exporter (remote write to Prometheus)
          prometheusremotewrite = {
            endpoint = "http://kube-prometheus-stack-prometheus.observability.svc.cluster.local:9090/api/v1/write"
            resource_to_telemetry_conversion = {
              enabled = true
            }
          }

          # OTLP exporter for Tempo (traces)
          "otlp/tempo" = {
            endpoint = "tempo.observability.svc.cluster.local:4317"
            tls = {
              insecure = true
            }
          }

          # OTLP HTTP exporter for Loki (logs)
          "otlphttp/loki" = {
            endpoint = "http://loki-gateway.observability.svc.cluster.local/otlp"
            tls = {
              insecure = true
            }
          }

          # Debug exporter (for debugging)
          debug = {
            verbosity = "basic"
          }
        }

        # Service pipelines - Define data flow
        service = {
          pipelines = {
            # Traces pipeline
            traces = {
              receivers  = ["otlp"]
              processors = ["memory_limiter", "k8sattributes", "resourcedetection", "attributes", "batch"]
              exporters  = ["otlp/tempo", "debug"]
            }

            # Metrics pipeline
            metrics = {
              receivers  = ["otlp", "prometheus"]
              processors = ["memory_limiter", "k8sattributes", "resourcedetection", "attributes", "batch"]
              exporters  = ["prometheusremotewrite"]
            }

            # Logs pipeline
            logs = {
              receivers  = ["otlp"]
              processors = ["memory_limiter", "k8sattributes", "resourcedetection", "attributes", "batch"]
              exporters  = ["otlphttp/loki", "debug"]
            }
          }

          # Telemetry (collector's own metrics)
          telemetry = {
            metrics = {
              address = ":8888"
            }
          }
        }
      }

      # Resources
      resources = {
        requests = {
          cpu    = "200m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }

      # Service Account (for Kubernetes API access)
      serviceAccount = {
        create = true
        name   = "otel-collector"
      }

      # RBAC for k8sattributes processor
      clusterRole = {
        create = true
        rules = [
          {
            apiGroups = [""]
            resources = ["pods", "namespaces", "nodes"]
            verbs     = ["get", "list", "watch"]
          },
          {
            apiGroups = ["apps"]
            resources = ["replicasets", "deployments", "daemonsets", "statefulsets"]
            verbs     = ["get", "list", "watch"]
          }
        ]
      }

      # Prometheus ServiceMonitor
      serviceMonitor = {
        enabled = true
      }

      # Pod annotations for auto-discovery
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "8888"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.observability,
    helm_release.kube_prometheus_stack,
    helm_release.tempo,
    helm_release.loki
  ]
}

# Output OTEL Collector endpoints for teams
output "otel_collector_grpc_endpoint" {
  description = "OpenTelemetry Collector gRPC endpoint (for application instrumentation)"
  value       = "opentelemetry-collector.observability.svc.cluster.local:4317"
}

output "otel_collector_http_endpoint" {
  description = "OpenTelemetry Collector HTTP endpoint (for application instrumentation)"
  value       = "http://opentelemetry-collector.observability.svc.cluster.local:4318"
}

output "otel_env_vars_example" {
  description = "Example environment variables for application OTEL instrumentation"
  value       = <<-EOT
    # Add these to your application pods:
    - name: OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://opentelemetry-collector.observability.svc.cluster.local:4318"
    - name: OTEL_EXPORTER_OTLP_PROTOCOL
      value: "http/protobuf"
    - name: OTEL_SERVICE_NAME
      value: "your-service-name"
    - name: OTEL_RESOURCE_ATTRIBUTES
      value: "service.namespace=$(POD_NAMESPACE),service.instance.id=$(POD_NAME)"
  EOT
}
