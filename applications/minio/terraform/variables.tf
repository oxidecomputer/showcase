// ============================================================
// Root variables - proxied into the module.
// Customers edit terraform.tfvars (copy from .example).
// ============================================================

variable "project_name" {
  description = "Oxide project to deploy into. Module creates it if create_project = true."
  type        = string
  default     = "minio-tf-poc"
}

variable "create_project" {
  description = "If true, the module creates the project. If false, the project must already exist."
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "VPC name for the MinIO cluster."
  type        = string
  default     = "minio-vpc"
}

variable "subnet_cidr" {
  description = "IPv4 CIDR for the cluster subnet. /24 gives 256 addresses, plenty for 4 MinIO + 2 LB + headroom."
  type        = string
  default     = "10.10.0.0/24"
}

variable "ubuntu_image_id" {
  description = "UUID of the Ubuntu 24.04 image to boot from. Must already exist in the project or be silo-accessible. Block size must be 512 for cloud-image GPT compatibility."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for ubuntu user on every instance. Single key, registered with Oxide and injected via cloud-init."
  type        = string
}

variable "minio_instance_count" {
  description = "MinIO cluster size. Must be a multiple of 4 (and >= 4) for clean EC:4 math. Default 4."
  type        = number
  default     = 4
  validation {
    condition     = var.minio_instance_count >= 4 && var.minio_instance_count % 4 == 0
    error_message = "minio_instance_count must be at least 4 and a multiple of 4."
  }
}

variable "minio_ncpus" {
  description = "vCPU per MinIO instance."
  type        = number
  default     = 4
}

variable "minio_memory_gib" {
  description = "RAM per MinIO instance, in GiB."
  type        = number
  default     = 16
}

variable "minio_boot_disk_gib" {
  description = "Boot disk size per MinIO instance, in GiB. Distributed (forced by Q-ENG-9)."
  type        = number
  default     = 30
}

variable "minio_data_disk_count" {
  description = "Data disks per MinIO instance. Default 4."
  type        = number
  default     = 4
}

variable "minio_data_disk_gib" {
  description = "Per-data-disk size, in GiB. Local."
  type        = number
  default     = 100
}

variable "lb_instance_count" {
  description = "LB cluster size. Default 2 (active/standby)."
  type        = number
  default     = 2
}

variable "lb_ncpus" {
  description = "vCPU per LB instance."
  type        = number
  default     = 2
}

variable "lb_memory_gib" {
  description = "RAM per LB instance, in GiB."
  type        = number
  default     = 4
}

variable "lb_boot_disk_gib" {
  description = "Boot disk size per LB instance, in GiB. Distributed (forced by Q-ENG-9)."
  type        = number
  default     = 20
}

variable "ip_pool_name" {
  description = "Name of the silo-linked IP pool for ephemeral and floating IPs. Verify with `oxide ip-pool list` first."
  type        = string
  default     = "public"
}

variable "oxide_credentials_for_failover" {
  description = "Contents of ~/.config/oxide/credentials.toml to drop on LB VMs for FIP failover. SENSITIVE. Pass via TF_VAR_oxide_credentials_for_failover env var, NOT in terraform.tfvars."
  type        = string
  sensitive   = true
}

variable "oxide_profile" {
  description = "Name of the profile inside credentials.toml that the LB watcher should use for FIP failover. The CLI errors with 'No profile specified' if credentials.toml has multiple [profile.X] sections and no default. Usually the silo name, e.g. 'employee-d1ce31bdc66a5171'."
  type        = string
}
