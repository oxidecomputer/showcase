# Builds an Oxide image that meets the requirements of a self-hosted Amp orb,
# excluding Desktop support.
# https://ampcode.com/docs/orbs/self-hosted#bring-your-own-image

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

locals {
  suffix = formatdate("YYYY-MM-DD-hhmmss", timestamp())
}

data "oxide-image" "source" {
  name    = var.source_image_name
  project = var.source_image_project != "" ? var.source_image_project : null
}

source "oxide-instance" "orb" {
  project            = var.project
  boot_disk_image_id = data.oxide-image.source.image_id
  boot_disk_size     = var.boot_disk_gib * 1073741824

  name     = "amp-orb-build-${local.suffix}"
  hostname = "amp-orb-build-${local.suffix}"

  vpc     = var.vpc
  subnet  = var.subnet
  ip_pool = var.ip_pool != "" ? var.ip_pool : null

  artifact_name        = "amp-orb-${local.suffix}"
  artifact_description = "Self-hosted Amp orb."
  artifact_os          = "debian"

  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_timeout  = "10m"
}

build {
  name    = "amp-orb"
  sources = ["source.oxide-instance.orb"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait",
      "sudo apt-get update",
      # Every orb: bash, coreutils, util-linux, CA certificates, sudo, and Git.
      # Portals and external agents: Node.js. Terminal: tmux. External agents:
      # curl. Recommended: ripgrep, gh, and openssh-client.
      "sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bash coreutils util-linux ca-certificates sudo git nodejs tmux curl ripgrep gh openssh-client",
      "sudo rm -rf /var/lib/apt/lists/*",
      # A `user` user and group with a writable home and passwordless sudo.
      "id user >/dev/null 2>&1 || sudo useradd --create-home --user-group --shell /bin/bash user",
      "echo 'user ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/90-amp-orb-user >/dev/null",
      "sudo chmod 0440 /etc/sudoers.d/90-amp-orb-user",
      # Install Amp as `user` so it can update itself, and link it where orbs
      # expect it.
      "sudo -u user -H bash -c 'curl -fsSL https://ampcode.com/install.sh | bash'",
      "sudo ln -sf /home/user/.amp/bin/amp /usr/local/bin/amp",
      "sudo -u user -H /usr/local/bin/amp --version",
    ]
  }

  # Reset the instance identity so cloud-init configures each orb from scratch
  # and runs the user-data dispatch.sh passes on every spawn.
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
