# kube-prometheus-stack Helm Chart
# Includes: Grafana, Prometheus, Prometheus Operator, Alertmanager, Node Exporter, Kube-state-metrics
# Provides metrics collection and visualization with RBAC-based namespace isolation

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.0.0" # Latest stable as of 2025
  namespace  = kubernetes_namespace.observability.metadata[0].name

  # Timeout increased for initial CRD installation
  timeout = 600

  values = [
    yamlencode({
      # Prometheus configuration
      prometheus = {
        prometheusSpec = {
          # Enable OpenTelemetry metrics receiver
          enableFeatures = ["otlp-write-receiver"]

          # Storage configuration
          retention = "30d"
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "50Gi"
                  }
                }
              }
            }
          }

          # Service monitor selector (discover all ServiceMonitors)
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false

          # External labels for multi-cluster (if needed later)
          externalLabels = {
            cluster = "aks-management-northeurope-prod"
          }

          # Pod anti-affinity for multi-node resilience
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
                          values   = ["prometheus"]
                        }
                      ]
                    }
                    topologyKey = "kubernetes.io/hostname"
                  }
                }
              ]
            }
          }
        }
      }

      # Grafana configuration
      grafana = {
        enabled = true

        # Deployment strategy (Recreate to avoid MultiAttachVolume errors with Azure Disk)
        deploymentStrategy = {
          type = "Recreate"
        }

        # Disable default datasources (we'll define our own)
        sidecar = {
          datasources = {
            defaultDatasourceEnabled = false
          }
        }

        # Admin credentials (change these!)
        adminPassword = "changeme" # TODO: Move to Azure Key Vault

        # Grafana configuration
        "grafana.ini" = {
          server = {
            root_url = "https://grafana.${azurerm_public_ip.ingress.ip_address}.nip.io"
          }

          # Azure AD SSO configuration (OAuth2)
          "auth.generic_oauth" = {
            enabled       = true
            name          = "Azure AD"
            allow_sign_up = true
            client_id     = "$__env{AZURE_AD_CLIENT_ID}"
            client_secret = "$__env{AZURE_AD_CLIENT_SECRET}"
            scopes        = "openid email profile"
            auth_url      = "https://login.microsoftonline.com/$__env{AZURE_AD_TENANT_ID}/oauth2/v2.0/authorize"
            token_url     = "https://login.microsoftonline.com/$__env{AZURE_AD_TENANT_ID}/oauth2/v2.0/token"
            api_url       = "https://graph.microsoft.com/v1.0/me"
            # Role mapping: Platform Team gets Admin, everyone else gets Editor (can use Explore, create dashboards)
            role_attribute_path = "contains(groups[*], 'AKS-Platform-Team') && 'Admin' || 'Editor'"
          }

          # Security settings
          security = {
            allow_embedding = false
          }

          # Users settings
          users = {
            auto_assign_org      = true
            auto_assign_org_role = "Editor" # Default role, overridden by OAuth mapping
          }
        }

        # Persistence for dashboards
        persistence = {
          enabled = true
          size    = "10Gi"
        }

        # Datasources (provisioned automatically)
        datasources = {
          "datasources.yaml" = {
            apiVersion = 1
            datasources = [
              {
                name      = "Prometheus"
                type      = "prometheus"
                url       = "http://kube-prometheus-stack-prometheus.observability.svc.cluster.local:9090"
                access    = "proxy"
                isDefault = true
                jsonData = {
                  timeInterval = "30s"
                }
              },
              {
                name   = "Loki"
                type   = "loki"
                url    = "http://loki-gateway.observability.svc.cluster.local"
                access = "proxy"
              },
              {
                name   = "Tempo"
                type   = "tempo"
                url    = "http://tempo.observability.svc.cluster.local:3100"
                access = "proxy"
                jsonData = {
                  tracesToLogsV2 = {
                    datasourceUid = "loki"
                    tags          = ["job", "instance", "pod", "namespace"]
                  }
                  tracesToMetrics = {
                    datasourceUid = "prometheus"
                    tags = [
                      {
                        key   = "service.name"
                        value = "service"
                      }
                    ]
                  }
                  serviceMap = {
                    datasourceUid = "prometheus"
                  }
                  nodeGraph = {
                    enabled = true
                  }
                }
              }
            ]
          }
        }

        # Dashboard providers (for namespace-scoped dashboards)
        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [
              {
                name            = "default"
                orgId           = 1
                folder          = ""
                type            = "file"
                disableDeletion = false
                editable        = true
                options = {
                  path = "/var/lib/grafana/dashboards/default"
                }
              }
            ]
          }
        }

        # Default dashboards
        dashboards = {
          default = {
            # Kubernetes cluster monitoring
            kubernetes-cluster-monitoring = {
              gnetId     = 7249
              revision   = 1
              datasource = "Prometheus"
            }
            # Node exporter full
            node-exporter-full = {
              gnetId     = 1860
              revision   = 37
              datasource = "Prometheus"
            }
          }
        }

        # Ingress (optional - for external access)
        ingress = {
          enabled = false # Enable when you add ingress controller
          # annotations = {
          #   "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
          # }
          # hosts = ["grafana.yourdomain.com"]
          # tls = [{
          #   secretName = "grafana-tls"
          #   hosts      = ["grafana.yourdomain.com"]
          # }]
        }

        # Environment variables for Azure AD OAuth
        envFromSecret = "grafana-azure-ad-secret"
      }

      # Alertmanager configuration
      alertmanager = {
        enabled = true
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
      }

      # Node exporter (collects node metrics)
      nodeExporter = {
        enabled = true
      }

      # Kube-state-metrics (Kubernetes object metrics)
      kubeStateMetrics = {
        enabled = true
      }

      # Prometheus Operator
      prometheusOperator = {
        enabled = true
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.observability,
    kubernetes_secret.grafana_azure_ad,
    azurerm_public_ip.ingress
  ]
}

# Azure AD OAuth secret for Grafana
# TODO: This should use Azure Key Vault in production
resource "kubernetes_secret" "grafana_azure_ad" {
  metadata {
    name      = "grafana-azure-ad-secret"
    namespace = kubernetes_namespace.observability.metadata[0].name
  }

  data = {
    AZURE_AD_TENANT_ID     = var.azure_ad_tenant_id
    AZURE_AD_CLIENT_ID     = var.azure_ad_grafana_client_id
    AZURE_AD_CLIENT_SECRET = var.azure_ad_grafana_client_secret
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace.observability
  ]
}

# Output Grafana access information
output "grafana_admin_password" {
  description = "Grafana admin password (change this!)"
  value       = "changeme"
  sensitive   = true
}

output "grafana_port_forward_command" {
  description = "Command to access Grafana via port-forward"
  value       = "kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80"
}
