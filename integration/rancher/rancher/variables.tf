variable "rancher_dns_name" {
  description = "Rancher DNS name."
  type        = string
  default     = ""
}

variable "rancher_version" {
  description = "Rancher Helm chart version."
  type        = string
  default     = "2.14.2"
}

variable "rancher_replicas" {
  description = "Number of Rancher replicas."
  type        = number
  default     = 3
}

variable "rancher_password" {
  description = "Rancher password. Used as the Helm bootstrapPassword and adopted as the permanent admin password by the nodedriver stage."
  type        = string
  sensitive   = true
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version."
  type        = string
  default     = "v1.17.2"
}
