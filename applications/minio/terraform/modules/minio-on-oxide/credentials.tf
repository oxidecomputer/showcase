// ============================================================
// MinIO root credentials.
// random_password generates them. They land in state (sensitive)
// and get rendered into each instance's cloud-init user_data.
// ============================================================

resource "random_id" "minio_user_suffix" {
  byte_length = 3
}

resource "random_password" "minio_root_password" {
  length           = 32
  special          = false  // keep it shell-safe for env files
  override_special = "!#-_=+"
  min_lower        = 4
  min_upper        = 4
  min_numeric      = 4
}

locals {
  minio_root_user     = "minio-admin-${random_id.minio_user_suffix.hex}"
  minio_root_password = random_password.minio_root_password.result
}
