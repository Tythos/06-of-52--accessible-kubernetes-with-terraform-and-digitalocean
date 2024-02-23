resource "digitalocean_kubernetes_cluster" "docluster" {
  name    = "docluster"
  region  = "sfo3"
  version = "1.29.1-do.0"

  node_pool {
    name       = "worker-pool"
    size       = "s-2vcpu-2gb"
    node_count = 3
  }
}
