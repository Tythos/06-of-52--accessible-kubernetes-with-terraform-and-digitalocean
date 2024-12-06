output "KUBECONFIG" {
  value     = module.doproject.KUBECONFIG
  sensitive = true
}

output "PUBLIC_IP" {
  value = module.icnamespace.PUBLIC_IP
}
