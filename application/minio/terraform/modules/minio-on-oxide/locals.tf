// ============================================================
// Computed values used across the module.
// ============================================================

locals {
  // Byte conversions - the Oxide TF provider takes sizes in bytes for memory and disk size.
  gib_bytes  = 1073741824
  minio_memory_bytes        = var.minio_memory_gib * local.gib_bytes
  minio_boot_disk_bytes     = var.minio_boot_disk_gib * local.gib_bytes
  minio_data_disk_bytes     = var.minio_data_disk_gib * local.gib_bytes
  lb_memory_bytes           = var.lb_memory_gib * local.gib_bytes
  lb_boot_disk_bytes        = var.lb_boot_disk_gib * local.gib_bytes

  // Subnet name within the VPC
  subnet_name = "minio-subnet"

  // Anti-affinity group names
  // Suffix '-tf' keeps Terraform-managed groups isolated from the manual lab
  // build's 'minio-spread' / 'lb-spread' groups, so the two deployments don't
  // fight each other for sled placement.
  minio_aa_group = "minio-tf-spread"
  lb_aa_group    = "lb-tf-spread"

  // Floating IP name - referenced by both floating-ip.tf and the LB
  // watcher cloud-init template so they stay in sync.
  fip_name = "minio-s3-endpoint"

  // Instance hostnames (also used in /etc/hosts)
  minio_hostnames = [for i in range(var.minio_instance_count) : "minio-inst-${i + 1}"]
  lb_hostnames    = [for i in range(var.lb_instance_count) : "lb-${i + 1}"]
}
