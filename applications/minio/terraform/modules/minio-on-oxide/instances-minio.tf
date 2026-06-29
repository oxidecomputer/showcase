// ============================================================
// MinIO compute: 4 instances + 4 local data disks each + anti-affinity.
//
// Boot disks: distributed (forced by Q-ENG-9 - local disks hardcoded
// to block size 4096, breaks image-sourced boot from a 512-block image).
// Data disks: local, blank, block size 4096.
//
// Anti-affinity group forces the 4 MinIO instances onto distinct sleds.
// ============================================================

resource "oxide_anti_affinity_group" "minio" {
  project_id  = local.project_id
  name        = local.minio_aa_group
  description = "Force MinIO nodes onto different sleds"
  policy      = "allow"
  // failure_domain is read-only and defaults to "sled" in this provider version.
}

// Boot disks - one per MinIO instance. Distributed, sourced from the Ubuntu image.
resource "oxide_disk" "minio_boot" {
  count           = var.minio_instance_count
  project_id      = local.project_id
  name            = "${local.minio_hostnames[count.index]}-os"
  description     = "Boot disk for ${local.minio_hostnames[count.index]}"
  size            = local.minio_boot_disk_bytes
  source_image_id = var.ubuntu_image_id
  // disk_type defaults to "distributed". Don't set block_size - it auto-calculates from image.
}

// Data disks - 4 per MinIO instance, total of N*4 = 16 for default config.
// Indexing: count.index maps to (node_index = floor(i/4), disk_index = i%4).
resource "oxide_disk" "minio_data" {
  count       = var.minio_instance_count * var.minio_data_disk_count
  project_id  = local.project_id
  name        = "${local.minio_hostnames[floor(count.index / var.minio_data_disk_count)]}-dd${(count.index % var.minio_data_disk_count) + 1}"
  description = "MinIO data disk ${(count.index % var.minio_data_disk_count) + 1} for ${local.minio_hostnames[floor(count.index / var.minio_data_disk_count)]}"
  size        = local.minio_data_disk_bytes
  disk_type   = "local"
  // block_size cannot be set when disk_type is "local" - the provider hardcodes it.
  // This is Q-ENG-9 confirmed: local disks ignore any block_size value and use 4096.
}

// MinIO instances. Each gets:
//   - boot disk + 4 data disks attached
//   - membership in the minio-tf-spread anti-affinity group
//   - one NIC in minio-subnet
//   - one ephemeral external IP from the configured pool (so we can SSH in)
//   - cloud-init user_data with placeholder bootstrap (cluster formation in Phase 2 null_resource)
resource "oxide_instance" "minio" {
  count       = var.minio_instance_count
  project_id  = local.project_id
  name        = local.minio_hostnames[count.index]
  hostname    = local.minio_hostnames[count.index]
  description = "MinIO node ${count.index + 1} of ${var.minio_instance_count}"
  ncpus       = var.minio_ncpus
  memory      = local.minio_memory_bytes

  boot_disk_id = oxide_disk.minio_boot[count.index].id

  disk_attachments = concat(
    [oxide_disk.minio_boot[count.index].id],
    [for d in range(var.minio_data_disk_count) :
      oxide_disk.minio_data[count.index * var.minio_data_disk_count + d].id
    ]
  )

  anti_affinity_groups = [oxide_anti_affinity_group.minio.id]

  ssh_public_keys = [oxide_ssh_key.default.id]

  external_ips = {
    ephemeral = [
      {
        pool_id = data.oxide_ip_pool.public.id
      }
    ]
  }

  network_interfaces = [
    {
      name        = "${local.minio_hostnames[count.index]}-nic"
      description = "Primary NIC for ${local.minio_hostnames[count.index]}"
      subnet_id   = oxide_vpc_subnet.minio.id
      vpc_id      = oxide_vpc.minio.id
      ip_config = {
        v4 = { ip = "auto" }
      }
    }
  ]

  // Placeholder user_data: enough to bootstrap an instance into a state ready
  // for the Phase 2 (cluster formation) null_resource. Real bootstrap and
  // cluster formation are layered on after the first apply, using the peer
  // IPs that only exist after the instances are created.
  user_data = base64encode(templatefile("${path.module}/cloud-init/minio-bootstrap.yaml.tftpl", {
    hostname            = local.minio_hostnames[count.index]
    ssh_public_key      = var.ssh_public_key
    minio_root_user     = local.minio_root_user
    minio_root_password = local.minio_root_password
  }))
}
