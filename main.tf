module "doproject" {
  source = "./doproject"
}

module "icnamespace" {
  source    = "./icnamespace"
  HOST_NAME = var.HOST_NAME
}

module "certsnamespace" {
  source      = "./certsnamespace"
  DO_TOKEN    = var.DO_TOKEN
  ACME_EMAIL  = var.ACME_EMAIL
  ACME_SERVER = var.ACME_SERVER
}

module "wwwnamespace" {
  source              = "./wwwnamespace"
  APP_NAME            = "www"
  HOST_NAME           = var.HOST_NAME
  CLUSTER_ISSUER_NAME = module.certsnamespace.CLUSTER_ISSUER_NAME
}
