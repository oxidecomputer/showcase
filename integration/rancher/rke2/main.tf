data "oxide_project" "rke2" {
  name = var.project
}

data "oxide_ip_pool" "ephemeral" {
  name = var.ip_pool_ephemeral
}

data "oxide_ip_pool" "floating" {
  name = var.ip_pool_floating
}

data "oxide_instance_external_ips" "node" {
  count       = var.node_count
  instance_id = oxide_instance.node[count.index].id
}

resource "random_password" "rke2_token" {
  length  = 32
  special = false
}

resource "tls_private_key" "rke2" {
  algorithm = "ED25519"
}

resource "oxide_ssh_key" "rke2" {
  name        = "rke2"
  description = "Ephemeral SSH key used by Terraform to fetch the RKE2 kubeconfig."
  public_key  = trimspace(tls_private_key.rke2.public_key_openssh)
}

locals {
  rke2_token = var.rke2_token != "" ? var.rke2_token : random_password.rke2_token.result

  node_names = [for i in range(var.node_count) : format("rke2-%02d", i + 1)]

  node_ips = [for i in range(var.node_count) : cidrhost(oxide_vpc_subnet.rke2.ipv4_block, 10 + i)]

  rancher_dns_name = var.rancher_dns_name != "" ? var.rancher_dns_name : "${oxide_floating_ip.rke2.ip}.sslip.io"

  tls_sans = concat(
    [local.rancher_dns_name, oxide_floating_ip.rke2.ip],
    local.node_ips,
    local.node_names,
  )
}

resource "oxide_floating_ip" "rke2" {
  project_id  = data.oxide_project.rke2.id
  name        = "rke2"
  description = "Stable external address for Rancher and the Kubernetes API."
  ip_pool_id  = data.oxide_ip_pool.floating.id
}

resource "oxide_vpc" "rke2" {
  project_id  = data.oxide_project.rke2.id
  name        = "rke2"
  description = "RKE2 cluster on SUSE Linux Micro."
  dns_name    = "rke2"
}

resource "oxide_vpc_subnet" "rke2" {
  vpc_id      = oxide_vpc.rke2.id
  description = "RKE2 cluster on SUSE Linux Micro."
  name        = "rke2"
  ipv4_block  = "192.168.0.0/16"
}

resource "oxide_vpc_firewall_rules" "rke2" {
  vpc_id = oxide_vpc.rke2.id

  rules = {
    allow-icmp = {
      description = "Allow ICMP."
      action      = "allow"
      direction   = "inbound"
      priority    = 65534
      status      = "enabled"
      filters     = { protocols = [{ type = "icmp" }] }
      targets     = [{ type = "vpc", value = oxide_vpc.rke2.name }]
    }
    allow-internal = {
      description = "Allow all traffic between nodes in the VPC."
      action      = "allow"
      direction   = "inbound"
      priority    = 65534
      status      = "enabled"
      filters     = { hosts = [{ type = "vpc", value = oxide_vpc.rke2.name }] }
      targets     = [{ type = "vpc", value = oxide_vpc.rke2.name }]
    }
    allow-cluster-ports = {
      description = "SSH, HTTP, HTTPS, Kubernetes API, and the RKE2 supervisor."
      action      = "allow"
      direction   = "inbound"
      priority    = 65534
      status      = "enabled"
      filters = {
        ports     = ["22", "80", "443", "6443", "9345"]
        protocols = [{ type = "tcp" }]
      }
      targets = [{ type = "vpc", value = oxide_vpc.rke2.name }]
    }
  }
}

resource "oxide_disk" "boot" {
  count           = var.node_count
  project_id      = data.oxide_project.rke2.id
  name            = "${local.node_names[count.index]}-boot"
  description     = "Boot disk for ${local.node_names[count.index]}"
  size            = var.boot_disk_size
  source_image_id = var.source_image_id
}

resource "oxide_instance" "node" {
  count            = var.node_count
  project_id       = data.oxide_project.rke2.id
  name             = local.node_names[count.index]
  hostname         = local.node_names[count.index]
  description      = "RKE2 cluster on SUSE Linux Micro."
  ncpus            = var.cpus
  memory           = var.memory
  start_on_create  = true
  ssh_public_keys  = concat([oxide_ssh_key.rke2.id], var.ssh_public_keys)
  boot_disk_id     = oxide_disk.boot[count.index].id
  disk_attachments = [oxide_disk.boot[count.index].id]

  network_interfaces = [{
    name        = "net0"
    description = "net0"
    vpc_id      = oxide_vpc.rke2.id
    subnet_id   = oxide_vpc_subnet.rke2.id
    ip_config   = { v4 = { ip = local.node_ips[count.index] } }
  }]

  external_ips = {
    ephemeral = [{ pool_id = data.oxide_ip_pool.ephemeral.id }]
    floating  = count.index == 0 ? [{ id = oxide_floating_ip.rke2.id }] : null
  }

  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    rke2_token   = local.rke2_token
    rke2_version = var.rke2_version
    rke2_channel = var.rke2_channel
    is_init_node = count.index == 0
    init_node_ip = local.node_ips[0]
    tls_sans     = local.tls_sans
    scc_regcode  = var.scc_regcode
    scc_email    = var.scc_email
  }))
}

resource "local_sensitive_file" "ssh_key" {
  content         = tls_private_key.rke2.private_key_openssh
  filename        = "${path.module}/.kube/id_ed25519"
  file_permission = "0600"
}

resource "terraform_data" "kubeconfig" {
  triggers_replace = [oxide_instance.node[0].id]

  connection {
    type        = "ssh"
    host        = oxide_floating_ip.rke2.ip
    user        = "sles"
    private_key = tls_private_key.rke2.private_key_openssh
  }

  provisioner "remote-exec" {
    inline = ["until test -r /etc/rancher/rke2/rke2.yaml; do sleep 5; done"]
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -i "${local_sensitive_file.ssh_key.filename}" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        sles@${oxide_floating_ip.rke2.ip} cat /etc/rancher/rke2/rke2.yaml \
        | sed 's#https://127.0.0.1:6443#https://${oxide_floating_ip.rke2.ip}:6443#' \
        > "${path.module}/.kube/config"
      chmod 600 "${path.module}/.kube/config"
    EOT
  }
}
