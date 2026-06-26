locals {
  oxide_credentials = provider::oxide::credentials(pathexpand(var.oxide_credentials_file))
}

resource "kubernetes_manifest" "oxide_nodedriver" {
  manifest = {
    apiVersion = "management.cattle.io/v3"
    kind       = "NodeDriver"
    metadata = {
      name = "oxide"
      annotations = {
        "privateCredentialFields"                    = "token"
        "publicCredentialFields"                     = "host"
        "nodedriver.cattle.io/file-to-field-aliases" = "userDataFile:userDataFile"
      }
    }
    spec = {
      active             = true
      addCloudCredential = true
      builtin            = false
      checksum           = var.oxide_nodedriver_checksum
      description        = "Oxide Rancher node driver."
      displayName        = "oxide"
      externalId         = ""
      uiUrl              = ""
      url                = "https://github.com/oxidecomputer/rancher-machine-driver-oxide/releases/download/${var.oxide_nodedriver_version}/docker-machine-driver-oxide"
      whitelistDomains   = ["github.com"]
    }
  }
}

resource "kubernetes_secret" "oxide" {
  metadata {
    name      = "cc-oxide"
    namespace = "cattle-global-data"
    annotations = {
      "field.cattle.io/name"      = "oxide"
      "field.cattle.io/driver"    = "oxide"
      "field.cattle.io/creatorId" = data.terraform_remote_state.rancher.outputs.rancher_user
    }
  }

  data = {
    "oxidecredentialConfig-host"  = local.oxide_credentials[var.oxide_profile].host
    "oxidecredentialConfig-token" = local.oxide_credentials[var.oxide_profile].token
  }

  depends_on = [kubernetes_manifest.oxide_nodedriver]
}
