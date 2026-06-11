variable "cluster_name" {
  description = "Name of the RKE2 cluster created via the Oxide node driver."
  type        = string
  default     = "oxide-k8s"
}

variable "kubernetes_version" {
  description = "RKE2 version for the cluster. Must be offered by this Rancher and within Longhorn's supported range."
  type        = string
  default     = "v1.33.11+rke2r1"
}

variable "control_plane_count" {
  description = "Number of control-plane/etcd nodes in the cluster."
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of worker nodes in the cluster."
  type        = number
  default     = 3
}

variable "control_plane_cpus" {
  description = "vCPUs per control-plane/etcd node."
  type        = string
  default     = "2"
}

variable "control_plane_memory" {
  description = "Memory per control-plane/etcd node."
  type        = string
  default     = "8 GiB"
}

variable "worker_cpus" {
  description = "vCPUs per worker node."
  type        = string
  default     = "2"
}

variable "worker_memory" {
  description = "Memory per worker node."
  type        = string
  default     = "8 GiB"
}

variable "boot_disk_size" {
  description = "Boot disk size per node."
  type        = string
  default     = "50 GiB"
}

variable "ssh_user" {
  description = "SSH user that Rancher will use to configure the node."
  type        = string
  default     = "sles"
}

variable "ssh_public_keys" {
  description = "Existing Oxide SSH key IDs to configure on the Kubernetes instances."
  type        = list(string)
  default     = []
}
