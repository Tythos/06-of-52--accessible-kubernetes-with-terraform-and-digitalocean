data "kubernetes_service" "lbicservice" {
  metadata {
    name      = "${helm_release.icrelease.name}-${helm_release.icrelease.chart}-controller"
    namespace = kubernetes_namespace.icnamespace.metadata[0].name
  }
}
