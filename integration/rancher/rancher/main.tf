locals {
  rancher_dns_name = var.rancher_dns_name != "" ? var.rancher_dns_name : data.terraform_remote_state.rke2.outputs.rancher_dns_name
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_version

  set {
    name  = "crds.enabled"
    value = "true"
  }

  wait    = true
  timeout = 600
}

resource "helm_release" "rancher" {
  name             = "rancher"
  namespace        = "cattle-system"
  create_namespace = true

  repository = "https://releases.rancher.com/server-charts/stable"
  chart      = "rancher"
  version    = var.rancher_version

  set {
    name  = "hostname"
    value = local.rancher_dns_name
  }

  set {
    name  = "replicas"
    value = var.rancher_replicas
  }

  set {
    name  = "bootstrapPassword"
    value = var.rancher_password
  }

  set {
    name  = "tls"
    value = "ingress"
  }

  set {
    name  = "ingress.tls.source"
    value = "rancher"
  }

  wait    = true
  timeout = 900

  depends_on = [helm_release.cert_manager]
}

resource "rancher2_bootstrap" "rke2" {
  initial_password = var.rancher_password
  password         = var.rancher_password

  depends_on = [helm_release.rancher]
}
