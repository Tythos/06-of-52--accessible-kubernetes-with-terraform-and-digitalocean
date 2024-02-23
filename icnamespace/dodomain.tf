resource "digitalocean_domain" "dodomain" {
  name       = var.HOST_NAME
  ip_address = data.kubernetes_service.lbicservice.status[0].load_balancer[0].ingress[0].ip
}
