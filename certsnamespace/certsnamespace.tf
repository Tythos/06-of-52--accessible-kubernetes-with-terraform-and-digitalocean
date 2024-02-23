resource "kubernetes_namespace" "certsnamespace" {
  metadata {
    name = "certsnamespace"
  }
}
