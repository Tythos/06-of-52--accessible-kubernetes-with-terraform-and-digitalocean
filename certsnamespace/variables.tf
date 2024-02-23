variable "DO_TOKEN" {
  type        = string
  description = "API token used to write to the DigitalOcean infrastructure"
  sensitive   = true
}

variable "ACME_EMAIL" {
  type        = string
  description = "Email address used for ACME cert registration and renewal proces"
}

variable "ACME_SERVER" {
  type        = string
  description = "Address used to configure ClusterIssuer for ACME cert request verification"
}
