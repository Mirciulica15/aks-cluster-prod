# Hubble UI deployment using Kubernetes manifests
# Since AKS manages Cilium, we deploy only the UI component directly

resource "kubernetes_service_account" "hubble_ui" {
  metadata {
    name      = "hubble-ui"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role" "hubble_ui" {
  metadata {
    name = "hubble-ui"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "services", "endpoints", "pods"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "hubble_ui" {
  metadata {
    name = "hubble-ui"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.hubble_ui.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.hubble_ui.metadata[0].name
    namespace = kubernetes_service_account.hubble_ui.metadata[0].namespace
  }
}

resource "kubernetes_config_map" "hubble_ui_nginx" {
  metadata {
    name      = "hubble-ui-nginx"
    namespace = "kube-system"
  }

  data = {
    "nginx.conf" = <<-EOT
      server {
          listen       8081;
          server_name  localhost;
          root /app;
          index index.html;
          client_max_body_size 1G;

          location / {
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;

              # CORS
              add_header Access-Control-Allow-Methods "GET, POST, PUT, HEAD, DELETE, OPTIONS";
              add_header Access-Control-Allow-Origin *;
              add_header Access-Control-Max-Age 1728000;
              add_header Access-Control-Expose-Headers content-length,grpc-status,grpc-message;
              add_header Access-Control-Allow-Headers range,keep-alive,user-agent,cache-control,content-type,content-transfer-encoding,x-accept-content-transfer-encoding,x-accept-response-streaming,x-user-agent,x-grpc-web,grpc-timeout;
              if ($request_method = OPTIONS) {
                  return 204;
              }
              # /CORS

              location /api {
                  proxy_http_version 1.1;
                  proxy_pass_request_headers on;
                  proxy_hide_header Access-Control-Allow-Origin;
                  proxy_pass http://127.0.0.1:8090;
              }

              location / {
                  try_files $uri $uri/ /index.html /index.html;
              }
          }
      }
    EOT
  }
}

resource "kubernetes_deployment" "hubble_ui" {
  #checkov:skip=CKV_K8S_30:TODO: Add security context to pods and containers
  #checkov:skip=CKV_K8S_28:TODO: Drop NET_RAW capability from containers
  #checkov:skip=CKV_K8S_29:TODO: Apply security context to deployment
  #checkov:skip=CKV_K8S_43:Using version tags instead of digests for easier updates and readability
  #checkov:skip=CKV_K8S_15:TODO: Set imagePullPolicy to Always
  #checkov:skip=CKV_K8S_8:TODO: Add liveness probes to containers
  #checkov:skip=CKV_K8S_9:TODO: Add readiness probes to containers
  metadata {
    name      = "hubble-ui"
    namespace = "kube-system"
    labels = {
      "k8s-app"                = "hubble-ui"
      "app.kubernetes.io/name" = "hubble-ui"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "k8s-app" = "hubble-ui"
      }
    }

    template {
      metadata {
        labels = {
          "k8s-app" = "hubble-ui"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.hubble_ui.metadata[0].name

        container {
          name  = "frontend"
          image = "quay.io/cilium/hubble-ui:v0.13.1"

          port {
            name           = "http"
            container_port = 8081
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }

          volume_mount {
            name       = "hubble-ui-nginx-conf"
            mount_path = "/etc/nginx/conf.d/default.conf"
            sub_path   = "nginx.conf"
          }
        }

        container {
          name  = "backend"
          image = "quay.io/cilium/hubble-ui-backend:v0.13.1"

          env {
            name  = "EVENTS_SERVER_PORT"
            value = "8090"
          }

          env {
            name  = "FLOWS_API_ADDR"
            value = "hubble-relay:443"
          }

          env {
            name  = "TLS_TO_RELAY_ENABLED"
            value = "true"
          }

          env {
            name  = "TLS_RELAY_SERVER_NAME"
            value = "hubble-relay.hubble-relay.cilium.io"
          }

          env {
            name  = "TLS_RELAY_CA_CERT_FILES"
            value = "/var/lib/hubble-relay/tls/ca.crt"
          }

          env {
            name  = "TLS_RELAY_CLIENT_CERT_FILE"
            value = "/var/lib/hubble-relay/tls/tls.crt"
          }

          env {
            name  = "TLS_RELAY_CLIENT_KEY_FILE"
            value = "/var/lib/hubble-relay/tls/tls.key"
          }

          port {
            name           = "grpc"
            container_port = 8090
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }

          volume_mount {
            name       = "hubble-relay-client-certs"
            mount_path = "/var/lib/hubble-relay/tls"
            read_only  = true
          }
        }

        volume {
          name = "hubble-ui-nginx-conf"
          config_map {
            name = kubernetes_config_map.hubble_ui_nginx.metadata[0].name
          }
        }

        volume {
          name = "hubble-relay-client-certs"
          secret {
            secret_name = "hubble-relay-client-certs"
            optional    = false
          }
        }
      }
    }
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

resource "kubernetes_service" "hubble_ui" {
  metadata {
    name      = "hubble-ui"
    namespace = "kube-system"
    labels = {
      "k8s-app" = "hubble-ui"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      "k8s-app" = "hubble-ui"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8081
    }
  }
}

# Access via: kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# Then open http://localhost:12000
