packer {
  required_plugins {
    oxide = {
      source  = "github.com/oxidecomputer/oxide"
      version = ">= 0.8.0"
    }
  }
}

locals {
  suffix = formatdate("YYYY-MM-DD", timestamp())
}

data "oxide-image" "source" {
  name    = var.source_image_name
  project = var.source_image_project != "" ? var.source_image_project : null
}

source "oxide-instance" "suse-linux-micro" {
  project            = var.project_name
  boot_disk_image_id = data.oxide-image.source.image_id
  boot_disk_size     = var.boot_disk_size

  name     = "suse-linux-micro-${local.suffix}"
  hostname = "suse-linux-micro-${local.suffix}"
  cpus     = var.vcpus
  memory   = var.memory

  vpc     = var.vpc
  subnet  = var.subnet
  ip_pool = var.ip_pool != "" ? var.ip_pool : null

  artifact_name        = "suse-linux-micro-${local.suffix}"

  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_timeout  = "10m"
}

build {
  name    = "suse-linux-micro"
  sources = ["source.oxide-instance.suse-linux-micro"]

  # Register with SUSE and install iSCSI packages.
  provisioner "shell" {
    environment_vars = [
      "SCC_REGCODE=${var.scc_regcode}",
      "SCC_EMAIL=${var.scc_email}",
    ]
    inline = [
      "set -euxo pipefail",
      "sudo transactional-update --non-interactive register -r \"$SCC_REGCODE\" -e \"$SCC_EMAIL\"",
      "sudo transactional-update --continue --non-interactive pkg install -y open-iscsi",
    ]
  }

  # Reboot into an environment with iSCSI packages loaded.
  provisioner "shell" {
    expect_disconnect = true
    inline            = ["sudo reboot"]
  }

  # Deregister with SUSE and confirm iSCSI packages are correctly installed.
  provisioner "shell" {
    pause_before = "30s"
    inline = [
      "set -euxo pipefail",
      "sudo transactional-update --non-interactive register -d",
      "rpm -q open-iscsi",
      "test -x /usr/sbin/iscsiadm",
      "sudo systemctl enable iscsid.socket iscsid.service",
      "echo iscsi_tcp | sudo tee /etc/modules-load.d/iscsi.conf",
    ]
  }

  # Reboot into deregistered environment.
  provisioner "shell" {
    expect_disconnect = true
    inline            = ["sudo reboot"]
  }

  # Seal the OS before creating an image.
  provisioner "shell" {
    pause_before = "30s"
    inline = [
      "set -euxo pipefail",
      "sudo SUSEConnect --status-text || true",
      "sudo rm -f /etc/zypp/credentials.d/* || true",
      "sudo zypper --non-interactive clean -a || true",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo cloud-init clean --logs --seed || true",
      "sudo rm -rf /var/log/* /tmp/* /var/tmp/* || true",
      "rm -f \"$HOME/.bash_history\" || true",
      "sudo sync",
    ]
  }
}
