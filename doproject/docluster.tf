resource "digitalocean_kubernetes_cluster" "docluster" {
  name    = "docluster"
  region  = "sfo3"
  version = "1.31.1-do.4"

  node_pool {
    name       = "worker-pool"
    size       = "s-2vcpu-2gb"
    node_count = 3
  }
}
