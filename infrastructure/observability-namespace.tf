# Observability Stack Namespace
# Central monitoring namespace for Grafana, Prometheus, Tempo, Loki, and OpenTelemetry Collector

resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
    labels = {
      name                                 = "observability"
      "pod-security.kubernetes.io/enforce" = "privileged" # Required for node exporters
    }
  }

  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}
