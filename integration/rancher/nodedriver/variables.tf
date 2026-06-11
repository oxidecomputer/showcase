variable "oxide_host" {
  description = "Oxide host the node driver targets."
  type        = string
}

variable "oxide_token" {
  description = "Oxide API token the node driver uses."
  type        = string
  sensitive   = true
}

variable "oxide_nodedriver_version" {
  description = "Release tag of oxidecomputer/rancher-machine-driver-oxide to install."
  type        = string
  default     = "v0.11.0"
}

variable "oxide_nodedriver_checksum" {
  description = "SHA256 of the docker-machine-driver-oxide binary for oxide_driver_version."
  type        = string
  default     = "d0fd21a622b90fb2f2c9d99e70036bdbf8eceb75072ee506ff8fb784e1178b09"
}
