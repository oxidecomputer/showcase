// ============================================================
// LB compute: 2 instances + anti-affinity group.
//
// Boot disks distributed (same Q-ENG-9 reason as MinIO).
// No data disks. No external IPs (FIP fronts the active LB, ProxyJump for the rest).
// ============================================================

resource "oxide_anti_affinity_group" "lb" {
  project_id  = local.project_id
  name        = local.lb_aa_group
  description = "Force LB instances onto different sleds"
  policy      = "allow"
  // failure_domain is read-only and defaults to "sled" in this provider version.
}

resource "oxide_disk" "lb_boot" {
  count           = var.lb_instance_count
  project_id      = local.project_id
  name            = "${local.lb_hostnames[count.index]}-os"
  description     = "Boot disk for ${local.lb_hostnames[count.index]}"
  size            = local.lb_boot_disk_bytes
  source_image_id = var.ubuntu_image_id
}

resource "oxide_instance" "lb" {
  count       = var.lb_instance_count
  project_id  = local.project_id
  name        = local.lb_hostnames[count.index]
  hostname    = local.lb_hostnames[count.index]
  description = "HAProxy LB ${count.index + 1} of ${var.lb_instance_count}"
  ncpus       = var.lb_ncpus
  memory      = local.lb_memory_bytes

  boot_disk_id     = oxide_disk.lb_boot[count.index].id
  disk_attachments = [oxide_disk.lb_boot[count.index].id]

  anti_affinity_groups = [oxide_anti_affinity_group.lb.id]
  ssh_public_keys      = [oxide_ssh_key.default.id]

  // No external_ips block. The Floating IP attaches to lb-1 separately (see floating-ip.tf).
  // SSH access via ProxyJump through a MinIO node during build, or via FIP once attached.

  network_interfaces = [
    {
      name        = "${local.lb_hostnames[count.index]}-nic"
      description = "Primary NIC for ${local.lb_hostnames[count.index]}"
      subnet_id   = oxide_vpc_subnet.minio.id
      vpc_id      = oxide_vpc.minio.id
      ip_config = {
        v4 = { ip = "auto" }
      }
    }
  ]

  user_data = base64encode(templatefile("${path.module}/cloud-init/lb-bootstrap.yaml.tftpl", {
    hostname                       = local.lb_hostnames[count.index]
    ssh_public_key                 = var.ssh_public_key
    oxide_credentials_for_failover = var.oxide_credentials_for_failover
    oxide_profile                  = var.oxide_profile
    project_name                   = var.project_name
    fip_name                       = local.fip_name
    // Peer is the other LB. For lb_instance_count=2 this flips between
    // index 0 and 1. Logic assumes a 2-LB pair; doesn't extend to N>2.
    peer_hostname = local.lb_hostnames[(count.index + 1) % var.lb_instance_count]
  }))
}
