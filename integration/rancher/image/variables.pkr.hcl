variable "source_image_name" {
  description = "Name of the SUSE Linux Micro source image to customize."
  type        = string
}

variable "source_image_project" {
  description = "Project containing the source image. Leave empty to fetch a silo image."
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project where the build instance and resulting image are created."
  type        = string
}

variable "scc_regcode" {
  description = "SUSE Customer Center (SCC) registration code used to temporarily register the build instance with SUSE to download packages."
  type        = string
  sensitive   = true
}

variable "scc_email" {
  description = "SUSE Customer Center (SCC) registration email."
  type        = string
}

variable "ip_pool" {
  description = "IP pool for the build instance's ephemeral external IP. Leave empty to use the silo's default IP pool. Packer must be able to reach the instance's external IP to perform provisioning."
  type        = string
  default     = ""
}

variable "vpc" {
  description = "VPC for the build instance's network interface."
  type        = string
  default     = "default"
}

variable "subnet" {
  description = "Subnet for the build instance's network interface."
  type        = string
  default     = "default"
}

variable "vcpus" {
  description = "vCPUs for the build instance."
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory for the throwaway build instance, in bytes."
  type        = number
  default     = 4294967296
}

variable "boot_disk_size" {
  description = "Boot disk size for the build instance, in bytes. Becomes the size of the produced image."
  type        = number
  default     = 34359738368
}

variable "ssh_username" {
  description = "SSH user on the SUSE Linux Micro image. Must have passwordless sudo."
  type        = string
  default     = "sles"
}
