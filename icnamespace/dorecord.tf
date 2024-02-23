resource "digitalocean_record" "dorecord" {
  domain = digitalocean_domain.dodomain.id
  type   = "A"
  name   = "*"
  value  = digitalocean_domain.dodomain.ip_address
}
