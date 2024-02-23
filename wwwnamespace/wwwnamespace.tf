resource "kubernetes_namespace" "wwwnamespace" {
  metadata {
    name = "wwwnamespace"
  }
}
