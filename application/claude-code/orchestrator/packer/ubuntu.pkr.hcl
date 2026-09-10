packer {
  required_plugins {
    oxide = {
      source  = "github.com/oxidecomputer/oxide"
      version = "~> 0.0"
    }
  }
}

variable "project" {
  description = "Project where Packer creates the build instance and image."
  type        = string
}

variable "source_image_name" {
  description = "Name of an Ubuntu cloud image with cloud-init."
  type        = string
}

variable "source_image_project" {
  description = "Project containing the source image; empty means a silo image."
  type        = string
  default     = ""
}

variable "ip_pool" {
  description = "External IP pool used to reach the temporary build instance."
  type        = string
  default     = ""
}

variable "vpc" {
  description = "VPC for the temporary build instance."
  type        = string
  default     = "default"
}

variable "subnet" {
  description = "Subnet for the temporary build instance."
  type        = string
  default     = "default"
}

variable "vcpus" {
  description = "vCPUs assigned to the temporary build instance."
  type        = number
  default     = 2
}

variable "memory_gib" {
  description = "Memory assigned to the temporary build instance, in GiB."
  type        = number
  default     = 4
}

variable "boot_disk_gib" {
  description = "Build instance and resulting image disk size, in GiB."
  type        = number
  default     = 20
}

variable "ssh_username" {
  description = "Source image user with passwordless sudo access."
  type        = string
  default     = "ubuntu"
}

variable "claude_version" {
  description = "Claude Code version installed in the orchestrator image."
  type        = string
  default     = "2.1.267"
}

locals {
  suffix = formatdate("YYYY-MM-DD-hhmmss", timestamp())
}

data "oxide-image" "source" {
  name    = var.source_image_name
  project = var.source_image_project != "" ? var.source_image_project : null
}

source "oxide-instance" "orchestrator" {
  project            = var.project
  boot_disk_image_id = data.oxide-image.source.image_id
  boot_disk_size     = var.boot_disk_gib * 1073741824

  name     = "claude-orchestrator-build-${local.suffix}"
  hostname = "claude-orchestrator-build-${local.suffix}"
  cpus     = var.vcpus
  memory   = var.memory_gib * 1073741824

  vpc     = var.vpc
  subnet  = var.subnet
  ip_pool = var.ip_pool != "" ? var.ip_pool : null

  artifact_name        = "claude-self-hosted-orchestrator-${local.suffix}"
  artifact_description = "Claude self-hosted environment orchestrator."
  artifact_os          = "ubuntu"

  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_timeout  = "10m"
}

build {
  name    = "claude-self-hosted-orchestrator"
  sources = ["source.oxide-instance.orchestrator"]

  provisioner "file" {
    sources = [
      "${path.root}/../bin",
      "${path.root}/../hooks",
      "${path.root}/../claude-self-hosted-orchestrator.service",
      "${path.root}/../claude-self-hosted-reaper.service",
      "${path.root}/../claude-self-hosted-reaper.timer",
      "${path.root}/../config.env.example",
      "${path.root}/install-deps.sh",
    ]
    destination = "/tmp/"
  }

  provisioner "shell" {
    environment_vars = ["CLAUDE_VERSION=${var.claude_version}"]
    inline = [
      "cloud-init status --wait",
      "sudo apt-get update",
      "sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl git gnupg jq xz-utils",
      "sudo rm -rf /var/lib/apt/lists/*",
      "id claude-self-hosted >/dev/null 2>&1 || sudo useradd --system --create-home --home-dir /var/lib/claude-self-hosted --shell /usr/sbin/nologin claude-self-hosted",
      "sudo install -d -m 0750 -o root -g claude-self-hosted /etc/claude-self-hosted /etc/claude-self-hosted/hooks",
      "sudo install -m 0755 /tmp/hooks/spawn-runner /etc/claude-self-hosted/hooks/spawn-runner",
      "sudo install -m 0755 /tmp/bin/claude-self-hosted-reaper /usr/local/bin/claude-self-hosted-reaper",
      "sudo install -m 0644 /tmp/claude-self-hosted-orchestrator.service /tmp/claude-self-hosted-reaper.service /tmp/claude-self-hosted-reaper.timer /etc/systemd/system/",
      "sudo install -m 0644 /tmp/config.env.example /etc/claude-self-hosted/config.env.example",
      "sudo --preserve-env=CLAUDE_VERSION /tmp/install-deps.sh",
      "sudo systemctl daemon-reload",
      "sudo systemctl disable claude-self-hosted-orchestrator.service claude-self-hosted-reaper.timer || true",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id /etc/ssh/ssh_host_*",
      "sudo cloud-init clean --logs --seed",
      "sudo sh -c 'rm -rf /var/log/* /tmp/* /var/tmp/*'",
      "rm -f \"$HOME/.bash_history\"",
      "sudo rm -f /root/.bash_history",
      "sudo sync",
    ]
  }
}
