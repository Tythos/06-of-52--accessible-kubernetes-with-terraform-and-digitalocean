terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.34.1"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.26.0"
    }
  }
}

provider "digitalocean" {
  token = var.DO_TOKEN
}

provider "kubernetes" {
  host                   = module.doproject.CLUSTER_HOST
  token                  = module.doproject.CLUSTER_TOKEN
  cluster_ca_certificate = module.doproject.CLUSTER_CA
}
