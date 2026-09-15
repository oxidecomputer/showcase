packer {
  required_plugins {
    oxide = {
      source  = "github.com/oxidecomputer/oxide"
      version = "~> 0.9"
    }
  }
}

variable "source_image_name" {
  type        = string
  description = "Name of the Ubuntu source image."
}

variable "source_image_project" {
  type        = string
  description = "Project containing the source image, or null for a silo image."
  default     = null
}

variable "project" {
  type        = string
  description = "Project in which to build and publish the image."
}

variable "artifact_name" {
  type        = string
  description = "Name of the resulting project image."
  default     = "buildkite-agent"
}

variable "boot_disk_size" {
  type        = number
  description = "Build instance boot disk size in bytes."
  default     = 16 * 1024 * 1024 * 1024
}

variable "cpus" {
  type        = number
  description = "Number of CPUs for the temporary build instance."
  default     = 2
}

variable "memory" {
  type        = number
  description = "Temporary build instance memory in bytes."
  default     = 8 * 1024 * 1024 * 1024
}

variable "vpc" {
  type        = string
  description = "VPC for the temporary build instance."
  default     = "default"
}

variable "subnet" {
  type        = string
  description = "Subnet for the temporary build instance."
  default     = "default"
}

variable "ip_pool" {
  type        = string
  description = "External IP pool, or null for the default pool."
  default     = null
}

variable "ssh_username" {
  type        = string
  description = "SSH user provided by the source image."
  default     = "ubuntu"
}

data "oxide-image" "source" {
  name    = var.source_image_name
  project = var.source_image_project
}

source "oxide-instance" "buildkite-agent" {
  project            = var.project
  boot_disk_image_id = data.oxide-image.source.image_id
  boot_disk_size     = var.boot_disk_size
  cpus               = var.cpus
  memory             = var.memory
  ip_pool            = var.ip_pool
  vpc                = var.vpc
  subnet             = var.subnet

  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_timeout  = "15m"

  artifact_name        = var.artifact_name
  artifact_description = "Ephemeral Buildkite agent for oxide-buildkite-stack"
}

build {
  sources = ["source.oxide-instance.buildkite-agent"]

  provisioner "shell" {
    inline          = ["cloud-init status --wait"]
    execute_command = "sudo env {{ .Vars }} bash '{{ .Path }}'"
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "NEEDRESTART_MODE=l",
    ]
    scripts = [
      "${path.root}/scripts/install-buildkite-agent.sh",
    ]
    execute_command = "sudo env {{ .Vars }} bash '{{ .Path }}'"
  }

  # Keep this last: it removes build access and makes cloud-init process the
  # controller's user data as a first boot when an agent instance is launched.
  provisioner "shell" {
    environment_vars = ["BUILD_USER=${var.ssh_username}"]
    script           = "${path.root}/scripts/finalize-image.sh"
    execute_command  = "sudo env {{ .Vars }} bash '{{ .Path }}'"
  }
}
