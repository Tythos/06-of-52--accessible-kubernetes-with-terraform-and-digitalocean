resource "kubernetes_service" "wwwservice" {
  metadata {
    name      = "wwwservice"
    namespace = kubernetes_namespace.wwwnamespace.metadata[0].name
  }

  spec {
    selector = {
      app = var.APP_NAME
    }

    port {
      port        = 80
      target_port = 80
    }
  }
}
