resource "helm_release" "longhorn" {
  name             = "longhorn"
  namespace        = "longhorn-system"
  create_namespace = true

  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = var.longhorn_version

  wait    = true
  timeout = 900

  set {
    name  = "defaultSettings.deletingConfirmationFlag"
    value = "true"
  }
}

resource "kubernetes_persistent_volume_claim" "fio" {
  metadata {
    name      = "fio-test"
    namespace = "default"
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }

  wait_until_bound = false

  depends_on = [helm_release.longhorn]
}

resource "kubernetes_job" "fio" {
  metadata {
    name      = "fio-test"
    namespace = "default"
  }

  spec {
    backoff_limit = 2

    template {
      metadata {
        labels = {
          app = "fio-test"
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name  = "fio"
          image = "alpine:3.20"

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
              set -e
              apk add --no-cache fio
              fio \
                --name=longhorn-randrw \
                --filename=/data/testfile \
                --size=4G \
                --rw=randrw \
                --rwmixread=70 \
                --bs=4k \
                --ioengine=libaio \
                --iodepth=16 \
                --direct=1 \
                --numjobs=1 \
                --runtime=60 \
                --time_based \
                --group_reporting
              rm -f /data/testfile
            EOT
          ]

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.fio.metadata[0].name
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "10m"
  }

  depends_on = [kubernetes_persistent_volume_claim.fio]
}
