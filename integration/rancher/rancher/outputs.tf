output "rancher_url" {
  description = "Rancher web console URL."
  value       = "https://${local.rancher_dns_name}"
}

output "rancher_token" {
  description = "Rancher API token."
  value       = rancher2_bootstrap.rke2.token
  sensitive   = true
}

output "rancher_user" {
  description = "Rancher user."
  value       = rancher2_bootstrap.rke2.user
}
