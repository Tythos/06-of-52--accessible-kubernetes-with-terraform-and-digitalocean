variable "APP_NAME" {
  type        = string
  description = "Name used to construct selector labels and as a subdomain used in building FQDNs for ingress"
}

variable "HOST_NAME" {
  type        = string
  description = "Domain under which ingress FQDNs are constructed"
}

variable "CLUSTER_ISSUER_NAME" {
  type        = string
  description = "Name used by ingress rules to identify where certificate requests within the cluster will be handled"
}
