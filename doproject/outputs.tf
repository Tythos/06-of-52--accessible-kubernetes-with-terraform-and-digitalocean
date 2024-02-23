output "KUBECONFIG" {
  value     = digitalocean_kubernetes_cluster.docluster.kube_config[0].raw_config
  sensitive = true
}

output "CLUSTER_HOST" {
  value = digitalocean_kubernetes_cluster.docluster.endpoint
}

output "CLUSTER_TOKEN" {
  value     = digitalocean_kubernetes_cluster.docluster.kube_config[0].token
  sensitive = true
}

output "CLUSTER_CA" {
  value     = base64decode(digitalocean_kubernetes_cluster.docluster.kube_config[0].cluster_ca_certificate)
  sensitive = true
}
