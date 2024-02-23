resource "kubernetes_secret" "dotoksecret" {
  metadata {
    name      = "dotoksecret"
    namespace = kubernetes_namespace.certsnamespace.metadata[0].name
  }

  data = {
    access-token = var.DO_TOKEN
  }
}
