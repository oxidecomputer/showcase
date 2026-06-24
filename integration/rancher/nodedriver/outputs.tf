output "cloud_credential_id" {
  description = "Rancher cloud-credential id (namespace:name) for the Oxide credential Secret."
  value       = "cattle-global-data:${kubernetes_secret.oxide.metadata[0].name}"
}
