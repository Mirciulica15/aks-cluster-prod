# Argo CD Namespace
# GitOps continuous delivery tool with multi-tenancy support
# Enables teams to manage their own applications with namespace-level isolation

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"

    labels = {
      name                                 = "argocd"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }

  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}
