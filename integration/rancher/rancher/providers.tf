terraform {
  required_version = ">= 1.9"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    rancher2 = {
      source  = "rancher/rancher2"
      version = "~> 14.1"
    }
  }
}

data "terraform_remote_state" "rke2" {
  backend = "local"
  config = {
    path = "${path.module}/../rke2/terraform.tfstate"
  }
}

provider "kubernetes" {
  config_path = data.terraform_remote_state.rke2.outputs.kubeconfig
}

provider "helm" {
  kubernetes {
    config_path = data.terraform_remote_state.rke2.outputs.kubeconfig
  }
}

provider "rancher2" {
  api_url   = "https://${local.rancher_dns_name}"
  bootstrap = true
  insecure  = true
}
