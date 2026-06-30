// ============================================================
// Module outputs. Sensitive values flagged so terraform output
// hides them by default; read with: terraform output -raw <name>
// ============================================================

output "project_id" {
  description = "Oxide project ID where everything lives."
  value       = local.project_id
}

output "vpc_id" {
  description = "minio-vpc ID."
  value       = oxide_vpc.minio.id
}

output "subnet_id" {
  description = "minio-subnet ID."
  value       = oxide_vpc_subnet.minio.id
}

output "floating_ip" {
  description = "Floating IP address (the S3 endpoint)."
  value       = oxide_floating_ip.s3_endpoint.ip
}

output "s3_endpoint" {
  description = "S3 API URL via the FIP."
  value       = "https://${oxide_floating_ip.s3_endpoint.ip}"
}

output "console_url" {
  description = "MinIO Console URL via the FIP (port 9443, exposed by HAProxy)."
  value       = "https://${oxide_floating_ip.s3_endpoint.ip}:9443"
}

output "minio_root_user" {
  description = "Generated MinIO root username."
  value       = local.minio_root_user
}

output "minio_root_password" {
  description = "Generated MinIO root password. Read with: terraform output -raw minio_root_password"
  value       = local.minio_root_password
  sensitive   = true
}

output "minio_instance_external_ips" {
  description = "Ephemeral external IPs of MinIO instances. SSH-accessible during the build."
  value = [
    for nic in oxide_instance.minio[*].attached_network_interfaces :
    "see oxide instance external-ip list output"
  ]
  // Note: external IPs are read separately via the Oxide CLI/API, the TF
  // provider doesn't surface them on the instance resource directly today.
}

output "minio_instance_private_ips" {
  description = "Private IPs of MinIO instances inside the VPC."
  value = [
    for inst in oxide_instance.minio :
    [for nic_name, nic in inst.attached_network_interfaces : nic.ip_stack.v4.ip][0]
  ]
}

output "minio_hostnames" {
  description = "Hostnames of MinIO instances (used in /etc/hosts during cluster formation)."
  value       = local.minio_hostnames
}

output "lb_instance_private_ips" {
  description = "Private IPs of LB instances inside the VPC."
  value = [
    for inst in oxide_instance.lb :
    [for nic_name, nic in inst.attached_network_interfaces : nic.ip_stack.v4.ip][0]
  ]
}

output "lb_hostnames" {
  description = "Hostnames of LB instances."
  value       = local.lb_hostnames
}

output "minio_anti_affinity_group_id" {
  description = "ID of the minio-tf-spread anti-affinity group."
  value       = oxide_anti_affinity_group.minio.id
}

output "lb_anti_affinity_group_id" {
  description = "ID of the lb-tf-spread anti-affinity group."
  value       = oxide_anti_affinity_group.lb.id
}
