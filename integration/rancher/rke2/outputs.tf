output "rke2_external_ip" {
  description = "RKE2 external IP."
  value       = oxide_floating_ip.rke2.ip
}

output "rancher_dns_name" {
  description = "DNS name for Rancher."
  value       = local.rancher_dns_name
}

output "rke2_token" {
  value     = local.rke2_token
  sensitive = true
}

output "kubeconfig" {
  description = "Absolute path to the cluster admin kubeconfig, consumed by downstream stages."
  value       = abspath("${path.module}/.kube/config")
  depends_on  = [terraform_data.kubeconfig]
}

output "project" {
  value = data.oxide_project.rke2.name
}

output "vpc" {
  value = oxide_vpc.rke2.name
}

output "subnet" {
  value = oxide_vpc_subnet.rke2.name
}

output "source_image_id" {
  value = var.source_image_id
}
