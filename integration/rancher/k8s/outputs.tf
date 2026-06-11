output "rancher_url" {
  description = "Rancher server URL."
  value       = data.terraform_remote_state.rancher.outputs.rancher_url
}

output "cluster_name" {
  description = "Name of the downstream RKE2 cluster."
  value       = rancher2_cluster_v2.oxide.name
}

output "cluster_v1_id" {
  description = "Rancher management (v1) cluster id for the downstream cluster."
  value       = rancher2_cluster_v2.oxide.cluster_v1_id
}

output "kubeconfig" {
  description = "Absolute path to the downstream cluster kubeconfig, consumed by downstream stages."
  value       = abspath(local_sensitive_file.kubeconfig.filename)
}
