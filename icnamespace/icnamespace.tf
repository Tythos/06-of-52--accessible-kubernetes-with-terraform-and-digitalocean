resource "kubernetes_namespace" "icnamespace" {
  metadata {
    name = "icnamespace"
  }
}
