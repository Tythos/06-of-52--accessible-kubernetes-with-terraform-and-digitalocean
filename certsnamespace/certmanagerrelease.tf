resource "helm_release" "certmanagerrelease" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.7.1"
  namespace  = kubernetes_namespace.certsnamespace.metadata[0].name

  set {
    name  = "installCRDs"
    value = "true"
  }
}
