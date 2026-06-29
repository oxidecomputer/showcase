// ============================================================
// Module variables.
// Defaults match what's exposed in the root - keep in sync.
// ============================================================

variable "project_name"   { type = string }
variable "create_project" { type = bool }
variable "vpc_name"       { type = string }
variable "subnet_cidr"    { type = string }
variable "ubuntu_image_id" { type = string }
variable "ssh_public_key" { type = string }

variable "minio_instance_count"   { type = number }
variable "minio_ncpus"             { type = number }
variable "minio_memory_gib"        { type = number }
variable "minio_boot_disk_gib"     { type = number }
variable "minio_data_disk_count"   { type = number }
variable "minio_data_disk_gib"     { type = number }

variable "lb_instance_count" { type = number }
variable "lb_ncpus"          { type = number }
variable "lb_memory_gib"     { type = number }
variable "lb_boot_disk_gib"  { type = number }

variable "ip_pool_name" { type = string }

variable "oxide_credentials_for_failover" {
  type      = string
  sensitive = true
}

variable "oxide_profile" {
  type = string
}
