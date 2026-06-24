locals {
  project             = data.terraform_remote_state.rke2.outputs.project
  image_id            = data.terraform_remote_state.rke2.outputs.source_image_id
  vpc                 = data.terraform_remote_state.rke2.outputs.vpc
  subnet              = data.terraform_remote_state.rke2.outputs.subnet
  cloud_credential_id = data.terraform_remote_state.nodedriver.outputs.cloud_credential_id
}

resource "kubernetes_manifest" "control_plane" {
  manifest = {
    apiVersion = "rke-machine-config.cattle.io/v1"
    kind       = "OxideConfig"
    metadata = {
      name      = "${var.cluster_name}-control-plane"
      namespace = "fleet-default"
    }
    project         = local.project
    bootDiskImageId = local.image_id
    vcpus           = var.control_plane_cpus
    memory          = var.control_plane_memory
    bootDiskSize    = var.boot_disk_size
    vpc             = local.vpc
    subnet          = local.subnet
    sshUser         = var.ssh_user
    sshPublicKey    = var.ssh_public_keys
  }
}

resource "kubernetes_manifest" "worker" {
  manifest = {
    apiVersion = "rke-machine-config.cattle.io/v1"
    kind       = "OxideConfig"
    metadata = {
      name      = "${var.cluster_name}-worker"
      namespace = "fleet-default"
    }
    project         = local.project
    bootDiskImageId = local.image_id
    vcpus           = var.worker_cpus
    memory          = var.worker_memory
    bootDiskSize    = var.boot_disk_size
    vpc             = local.vpc
    subnet          = local.subnet
    sshUser         = var.ssh_user
    sshPublicKey    = var.ssh_public_keys
    additionalDisk  = ["size=10 GiB,label=longhorn,type=local"]
    userDataFile    = file("${path.module}/worker-userdata.yaml")
  }
}

resource "rancher2_cluster_v2" "oxide" {
  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  rke_config {
    machine_pools {
      name                         = "control-plane"
      cloud_credential_secret_name = local.cloud_credential_id
      control_plane_role           = true
      etcd_role                    = true
      worker_role                  = false
      quantity                     = var.control_plane_count

      machine_config {
        kind = "OxideConfig"
        name = kubernetes_manifest.control_plane.manifest.metadata.name
      }
    }

    machine_pools {
      name                         = "worker"
      cloud_credential_secret_name = local.cloud_credential_id
      control_plane_role           = false
      etcd_role                    = false
      worker_role                  = true
      quantity                     = var.worker_count

      machine_labels = {
        "node.longhorn.io/create-default-disk" = "true"
      }

      machine_config {
        kind = "OxideConfig"
        name = kubernetes_manifest.worker.manifest.metadata.name
      }
    }
  }

  depends_on = [
    kubernetes_manifest.control_plane,
    kubernetes_manifest.worker,
  ]
}

resource "local_sensitive_file" "kubeconfig" {
  content         = rancher2_cluster_v2.oxide.kube_config
  filename        = "${path.module}/.kube/config"
  file_permission = "0600"
}
