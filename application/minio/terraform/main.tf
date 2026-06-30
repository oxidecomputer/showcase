// ============================================================
// Root config - invokes the minio-on-oxide module.
// ============================================================

module "minio_on_oxide" {
  source = "./modules/minio-on-oxide"

  project_name                   = var.project_name
  create_project                 = var.create_project
  vpc_name                       = var.vpc_name
  subnet_cidr                    = var.subnet_cidr
  ubuntu_image_id                = var.ubuntu_image_id
  ssh_public_key                 = var.ssh_public_key
  minio_instance_count           = var.minio_instance_count
  minio_ncpus                    = var.minio_ncpus
  minio_memory_gib               = var.minio_memory_gib
  minio_boot_disk_gib            = var.minio_boot_disk_gib
  minio_data_disk_count          = var.minio_data_disk_count
  minio_data_disk_gib            = var.minio_data_disk_gib
  lb_instance_count              = var.lb_instance_count
  lb_ncpus                       = var.lb_ncpus
  lb_memory_gib                  = var.lb_memory_gib
  lb_boot_disk_gib               = var.lb_boot_disk_gib
  ip_pool_name                   = var.ip_pool_name
  oxide_credentials_for_failover = var.oxide_credentials_for_failover
  oxide_profile                  = var.oxide_profile
}
