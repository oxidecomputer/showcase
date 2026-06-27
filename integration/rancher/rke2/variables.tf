variable "project" {
  description = "Project to create the RKE2 cluster within."
  type        = string
}

variable "source_image_id" {
  description = "ID of the SUSE Linux Micro image in the silo or project."
  type        = string
}

variable "ssh_public_keys" {
  description = "Existing Oxide SSH key IDs to configure on the RKE2 instances."
  type        = list(string)
  default     = []
}

variable "rancher_dns_name" {
  description = "DNS name to use for the future Rancher installation. When unset, uses a sslip.io DNS name."
  type        = string
  default     = ""
}

variable "rke2_token" {
  description = "Shared RKE2 cluster join token. Empty generates a random one."
  type        = string
  default     = ""
  sensitive   = true
}

variable "rke2_version" {
  description = "RKE2 version to install (e.g., v1.32.13+rke2r1). Takes precedence over rke2_channel when set. Pin this to a version on Rancher's support matrix."
  type        = string
  default     = "v1.32.13+rke2r1"
}

variable "rke2_channel" {
  description = "RKE2 release channel (e.g., v1.32) to install from when rke2_version is empty."
  type        = string
  default     = "v1.32"
}

variable "ephemeral_ip_pool_id" {
  description = "IP pool ID to allocate an ephemeral IP from. Used for SSH on the RKE2 nodes. Leave unset to use the silo's default IP pool."
  type        = string
  default     = ""
}

variable "floating_ip_pool_id" {
  description = "IP pool ID to allocate a floating IP from. Used to access the Kubernetes API. Leave unset to use the silo's default IP pool."
  type        = string
  default     = ""
}

variable "node_count" {
  description = "Number of RKE2 nodes to create."
  type        = number
  default     = 3
}

variable "cpus" {
  description = "vCPUs per node."
  type        = number
  default     = 4
}

variable "memory" {
  description = "Memory per node, in bytes."
  type        = number
  default     = 17179869184
}

variable "boot_disk_size" {
  description = "Boot disk size per node, in bytes."
  type        = number
  default     = 68719476736
}

variable "scc_regcode" {
  description = "SUSE Customer Center (SCC) registration code. Empty skips registration since RKE2 does not require it."
  type        = string
  default     = ""
  sensitive   = true
}

variable "scc_email" {
  description = "SUSE Customer Center (SCC) email address."
  type        = string
  default     = ""
}
