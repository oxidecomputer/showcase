// ============================================================
// Floating IP: customer-facing S3 endpoint, attached to lb-1.
// Falls over to lb-2 via the watcher script we install on the LBs.
// ============================================================

// Look up the IP pool by name so we can use its ID.
data "oxide_ip_pool" "public" {
  name = var.ip_pool_name
}

resource "oxide_floating_ip" "s3_endpoint" {
  project_id  = local.project_id
  name        = local.fip_name
  description = "S3 endpoint for MinIO cluster, attaches to active LB VM"
  ip_pool_id  = data.oxide_ip_pool.public.id
}

// Attach the FIP to lb-1 at create time via the CLI.
// The watcher on lb-2 will reattach it via the Oxide API on failover.
// We do NOT use the instance resource's external_ips.floating block, because we want
// the attach/detach to be controllable outside Terraform's lifecycle (the failover
// script needs to detach/attach without TF treating it as drift).
resource "null_resource" "fip_attach_lb1" {
  // All values that the destroy provisioner needs MUST live in triggers,
  // because destroy provisioners cannot reference vars or other resources.
  triggers = {
    project_name    = var.project_name
    fip_name        = oxide_floating_ip.s3_endpoint.name
    lb1_name        = oxide_instance.lb[0].name
    fip_id          = oxide_floating_ip.s3_endpoint.id
    lb1_instance_id = oxide_instance.lb[0].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Retry attach up to 6 times with 10s delays. Oxide control plane
      # returns 503 transiently when busy provisioning other resources.
      for attempt in 1 2 3 4 5 6; do
        if oxide floating-ip attach \
            --project ${self.triggers.project_name} \
            --floating-ip ${self.triggers.fip_name} \
            --kind instance \
            --parent ${self.triggers.lb1_name}; then
          echo "FIP attach succeeded on attempt $attempt"
          exit 0
        fi
        echo "FIP attach attempt $attempt failed, retrying in 10s..."
        sleep 10
      done
      echo "FIP attach failed after 6 attempts" >&2
      exit 1
    EOT
  }

  // On destroy, detach so the floating IP can be deleted cleanly.
  // Retry on transient 503s. `|| true` at the end so destroy proceeds
  // even if detach ultimately fails (the FIP delete will retry too).
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      for attempt in 1 2 3 4 5 6; do
        if oxide floating-ip detach \
            --project ${self.triggers.project_name} \
            --floating-ip ${self.triggers.fip_name}; then
          echo "FIP detach succeeded on attempt $attempt"
          exit 0
        fi
        sleep 10
      done
      echo "FIP detach gave up after 6 attempts (continuing)"
      true
    EOT
  }
}
