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
  }
}

data "terraform_remote_state" "k8s" {
  backend = "local"
  config = {
    path = "${path.module}/../k8s/terraform.tfstate"
  }
}

provider "kubernetes" {
  config_path = data.terraform_remote_state.k8s.outputs.kubeconfig
}

provider "helm" {
  kubernetes {
    config_path = data.terraform_remote_state.k8s.outputs.kubeconfig
  }
}
