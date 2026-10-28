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
  description = "Name of a Debian 13 cloud image with cloud-init."
  type        = string
  default     = "debian-13"
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

variable "boot_disk_gib" {
  description = "Build instance and resulting image disk size, in GiB."
  type        = number
  default     = 20
}

variable "ssh_username" {
  description = "Source image user with passwordless sudo access."
  type        = string
  default     = "debian"
}

variable "claude_version" {
  description = "Claude Code version installed in the runner image."
  type        = string
  default     = "2.1.312"
}

locals {
  suffix = formatdate("YYYY-MM-DD-hhmmss", timestamp())
}

data "oxide-image" "source" {
  name    = var.source_image_name
  project = var.source_image_project != "" ? var.source_image_project : null
}

source "oxide-instance" "runner" {
  project            = var.project
  boot_disk_image_id = data.oxide-image.source.image_id
  boot_disk_size     = var.boot_disk_gib * 1073741824

  name     = "claude-runner-build-${local.suffix}"
  hostname = "claude-runner-build-${local.suffix}"

  vpc     = var.vpc
  subnet  = var.subnet
  ip_pool = var.ip_pool != "" ? var.ip_pool : null

  artifact_name        = "claude-self-hosted-runner-${local.suffix}"
  artifact_description = "Claude self-hosted environment runner."
  artifact_os          = "debian"

  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_timeout  = "10m"
}

build {
  name    = "claude-self-hosted-runner"
  sources = ["source.oxide-instance.runner"]

  provisioner "file" {
    sources = [
      "${path.root}/hooks",
      "${path.root}/claude-runner.service",
      "${path.root}/install-claude.sh",
    ]
    destination = "/tmp/"
  }

  provisioner "shell" {
    environment_vars = ["CLAUDE_VERSION=${var.claude_version}"]
    inline = [
      "cloud-init status --wait",
      "sudo apt-get update",
      "sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl git gnupg jq",
      "sudo rm -rf /var/lib/apt/lists/*",
      "id claude-self-hosted >/dev/null 2>&1 || sudo useradd --system --home-dir /var/lib/claude-self-hosted --shell /usr/sbin/nologin claude-self-hosted",
      "sudo install -d -m 0755 /etc/claude-self-hosted/hooks",
      "sudo install -m 0755 /tmp/hooks/post-session /etc/claude-self-hosted/hooks/post-session",
      "sudo install -m 0644 /tmp/claude-runner.service /etc/systemd/system/claude-runner.service",
      "sudo --preserve-env=CLAUDE_VERSION /tmp/install-claude.sh",
      "sudo systemctl daemon-reload",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id /etc/ssh/ssh_host_*",
      "sudo cloud-init clean --logs --seed",
      "sudo sh -c 'rm -rf /var/log/* /tmp/* /var/tmp/*'",
      "rm -f \"$HOME/.bash_history\" \"$HOME/.ssh/authorized_keys\"",
      "sudo rm -f /root/.bash_history",
      "sudo sync",
    ]
  }
}
