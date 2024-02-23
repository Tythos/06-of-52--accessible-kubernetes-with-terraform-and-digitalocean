resource "kubernetes_ingress_v1" "wwwingress" {
  metadata {
    name      = "wwwingress"
    namespace = kubernetes_namespace.wwwnamespace.metadata[0].name
  }

  spec {
    rule {
      host = "${var.APP_NAME}.${var.HOST_NAME}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.wwwservice.metadata[0].name

              port {
                number = kubernetes_service.wwwservice.spec[0].port[0].port
              }
            }
          }
        }
      }
    }
  }
}
