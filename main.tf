module "doproject" {
  source = "./doproject"
}

module "wwwnamespace" {
  source   = "./wwwnamespace"
  APP_NAME = "www"
  HOST_NAME = var.HOST_NAME
}
