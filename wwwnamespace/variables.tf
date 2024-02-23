variable "APP_NAME" {
  type        = string
  description = "Name used to construct selector labels and as a subdomain used in building FQDNs for ingress"
}

variable "HOST_NAME" {
  type        = string
  description = "Domain under which ingress FQDNs are constructed"
}
