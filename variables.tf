variable "DO_TOKEN" {
  type        = string
  description = "API token for DigitalOcean provider; pass using environmental variable $TF_VAR_DO_TOKEN"
}

variable "HOST_NAME" {
  type        = string
  description = "'Base' host name to which app names will be prepended to construct FQDNs"
}

variable "ACME_EMAIL" {
  type        = string
  description = "Email address used for ACME cert registration and renewal proces"
}

variable "ACME_SERVER" {
  type        = string
  description = "Address used to configure ClusterIssuer for ACME cert request verification"
}
