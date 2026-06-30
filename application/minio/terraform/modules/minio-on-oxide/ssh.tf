// ============================================================
// Register the SSH public key on the current Oxide user.
// All instances reference this key via `ssh_public_keys = [...]`.
// ============================================================

resource "oxide_ssh_key" "default" {
  name        = "minio-on-oxide-tf"
  description = "SSH key managed by the minio-on-oxide Terraform module"
  public_key  = var.ssh_public_key
}
