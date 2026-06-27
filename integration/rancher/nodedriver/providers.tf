terraform {
  required_version = ">= 1.9"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    oxide = {
      source  = "oxidecomputer/oxide"
      version = ">= 0.20.1"
    }
  }
}

data "terraform_remote_state" "rke2" {
  backend = "local"
  config = {
    path = "${path.module}/../rke2/terraform.tfstate"
  }
}

data "terraform_remote_state" "rancher" {
  backend = "local"
  config = {
    path = "${path.module}/../rancher/terraform.tfstate"
  }
}

provider "kubernetes" {
  config_path = data.terraform_remote_state.rke2.outputs.kubeconfig
}
