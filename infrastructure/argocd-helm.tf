# Argo CD Helm Chart
# GitOps continuous delivery tool for Kubernetes
# Features: Azure AD SSO, namespace isolation via AppProjects, RBAC

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.0" # Latest stable as of 2025
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Timeout for initial installation
  timeout = 600

  values = [
    yamlencode({
      # Global configuration
      global = {
        # Domain configuration for Argo CD
        domain = "argocd.${azurerm_public_ip.ingress.ip_address}.nip.io"

        # Network policy (optional, can enable later)
        networkPolicy = {
          create  = false
          enabled = false
        }
      }

      # Argo CD Server configuration
      server = {
        # Replicas for HA
        replicas = 2

        # Resources
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        # Service configuration
        service = {
          type = "ClusterIP"
        }

        # Ingress (disabled for now, enable when you add ingress controller)
        ingress = {
          enabled = false
          # annotations = {
          #   "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
          # }
          # hosts = ["argocd.yourdomain.com"]
          # tls = [{
          #   secretName = "argocd-tls"
          #   hosts      = ["argocd.yourdomain.com"]
          # }]
        }

        # Metrics for Prometheus
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
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
                        values   = ["argocd-server"]
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

      # Argo CD Controller (Application reconciliation)
      controller = {
        replicas = 1

        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "2000m"
            memory = "2Gi"
          }
        }

        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
      }

      # Argo CD Repo Server (Git repository interaction)
      repoServer = {
        replicas = 2

        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
        }

        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }

        # Pod anti-affinity
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
                        values   = ["argocd-repo-server"]
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

      # Redis for caching
      redis = {
        enabled = true

        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
      }

      # Dex (OAuth2/OIDC provider - handles Azure AD integration)
      dex = {
        enabled = true

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

        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
      }

      # Application Set Controller (for app-of-apps pattern)
      applicationSet = {
        enabled  = true
        replicas = 1

        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
      }

      # Notifications controller (optional, for Slack/Teams notifications)
      notifications = {
        enabled = false # Can enable later if teams want notifications
      }

      # Argo CD configuration
      configs = {
        # Main Argo CD configuration
        cm = {
          # URL for OAuth redirect
          url = "https://argocd.${azurerm_public_ip.ingress.ip_address}.nip.io"

          # Azure AD SSO via Dex
          "dex.config" = yamlencode({
            connectors = [
              {
                type = "microsoft"
                id   = "azure-ad"
                name = "Azure AD"
                config = {
                  clientID     = var.azure_ad_argocd_client_id
                  clientSecret = var.azure_ad_argocd_client_secret
                  tenant       = var.azure_ad_tenant_id
                  redirectURI  = "https://argocd.${azurerm_public_ip.ingress.ip_address}.nip.io/api/dex/callback"
                  # Don't filter groups - allow all groups to be returned
                }
              }
            ]
          })

          # Admin enabled (can disable after SSO is working)
          "admin.enabled" = "true"

          # Resource customizations for health checks
          "resource.customizations" = yamlencode({
            "argoproj.io/Application" = {
              health = {
                lua = <<-LUA
                  hs = {}
                  hs.status = "Progressing"
                  hs.message = ""
                  if obj.status ~= nil then
                    if obj.status.health ~= nil then
                      hs.status = obj.status.health.status
                      if obj.status.health.message ~= nil then
                        hs.message = obj.status.health.message
                      end
                    end
                  end
                  return hs
                LUA
              }
            }
          })

          # Application instance label key
          "application.instanceLabelKey" = "argocd.argoproj.io/instance"
        }

        # RBAC configuration
        rbac = {
          # Policy CSV for role-based access control
          "policy.csv" = <<-CSV
            # Platform Admin - Full access to everything
            g, AKS-Platform-Team, role:admin

            # Team Alpha - Limited to their AppProject and namespaces
            p, role:team-alpha-admin, applications, *, team-alpha/*, allow
            p, role:team-alpha-admin, repositories, *, team-alpha/*, allow
            g, AKS-Team-Alpha, role:team-alpha-admin

            # Team Beta - Limited to their AppProject and namespaces
            p, role:team-beta-admin, applications, *, team-beta/*, allow
            p, role:team-beta-admin, repositories, *, team-beta/*, allow
            g, AKS-Team-Beta, role:team-beta-admin

            # Viewer role - Read-only access to all applications
            p, role:viewer, applications, get, */*, allow
            p, role:viewer, applications, list, */*, allow
            g, AKS-Developers, role:viewer
          CSV

          # Default policy (deny all unless explicitly allowed)
          "policy.default" = "role:readonly"

          # Scopes for SSO
          "scopes" = "[groups, email]"
        }

        # Repository credentials (optional, add later)
        credentialTemplates = {}

        # Repository configuration (optional, add later)
        repositories = {}

        # Secret management (optional, integrate with Azure Key Vault later)
        secret = {
          # argocdServerAdminPassword will be auto-generated if not set
          # Can set manually for known password
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    kubernetes_secret.argocd_azure_ad,
    helm_release.kube_prometheus_stack,
    azurerm_public_ip.ingress
  ]
}

# Azure AD OAuth secret for Argo CD
resource "kubernetes_secret" "argocd_azure_ad" {
  metadata {
    name      = "argocd-azure-ad-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  data = {
    tenant_id     = var.azure_ad_tenant_id
    client_id     = var.azure_ad_argocd_client_id
    client_secret = var.azure_ad_argocd_client_secret
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace.argocd
  ]
}

# Output Argo CD access information
output "argocd_admin_password_command" {
  description = "Command to retrieve Argo CD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_command" {
  description = "Command to access Argo CD UI via port-forward"
  value       = "kubectl port-forward -n argocd svc/argocd-server 8080:443"
}

output "argocd_server_url" {
  description = "Argo CD server URL (update when ingress is configured)"
  value       = "https://argocd.yourdomain.com"
}
