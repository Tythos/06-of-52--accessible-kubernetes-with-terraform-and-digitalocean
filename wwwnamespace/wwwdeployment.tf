resource "kubernetes_deployment" "wwwdeployment" {
  metadata {
    name      = "wwwdeployment"
    namespace = kubernetes_namespace.wwwnamespace.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = var.APP_NAME
      }
    }

    template {
      metadata {
        labels = {
          app = var.APP_NAME
        }
      }

      spec {
        container {
          image = "nginx"
          name  = "nginx"
        }
      }
    }
  }
}
