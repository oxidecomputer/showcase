// ============================================================
// Root outputs - proxied from the module.
// `terraform output -raw <name>` to read sensitive values.
// ============================================================

output "floating_ip" {
  description = "Customer-facing S3 endpoint IP."
  value       = module.minio_on_oxide.floating_ip
}

output "s3_endpoint" {
  description = "S3 API URL (TLS-terminated at HAProxy)."
  value       = module.minio_on_oxide.s3_endpoint
}

output "console_url" {
  description = "MinIO Console URL via the Floating IP."
  value       = module.minio_on_oxide.console_url
}

output "minio_root_user" {
  description = "MinIO root username."
  value       = module.minio_on_oxide.minio_root_user
}

output "minio_root_password" {
  description = "MinIO root password. Read via: terraform output -raw minio_root_password"
  value       = module.minio_on_oxide.minio_root_password
  sensitive   = true
}

output "minio_instance_external_ips" {
  description = "External IPs of MinIO instances for SSH access during validation."
  value       = module.minio_on_oxide.minio_instance_external_ips
}

output "minio_instance_private_ips" {
  description = "Private IPs of MinIO instances inside the VPC."
  value       = module.minio_on_oxide.minio_instance_private_ips
}

output "lb_instance_private_ips" {
  description = "Private IPs of LB instances. LBs have no external IPs - reach via ProxyJump through a MinIO node."
  value       = module.minio_on_oxide.lb_instance_private_ips
}
