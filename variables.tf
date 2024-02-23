variable "DO_TOKEN" {
  type        = string
  description = "API token for DigitalOcean provider; pass using environmental variable $TF_VAR_DO_TOKEN"
}

variable "HOST_NAME" {
  type        = string
  description = "'Base' host name to which app names will be prepended to construct FQDNs"
}
