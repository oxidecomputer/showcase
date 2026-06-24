terraform {
  required_version = ">= 1.9"

  required_providers {
    rancher2 = {
      source  = "rancher/rancher2"
      version = "~> 14.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
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

data "terraform_remote_state" "nodedriver" {
  backend = "local"
  config = {
    path = "${path.module}/../nodedriver/terraform.tfstate"
  }
}

provider "rancher2" {
  api_url   = data.terraform_remote_state.rancher.outputs.rancher_url
  token_key = data.terraform_remote_state.rancher.outputs.rancher_token
  insecure  = true
}

provider "kubernetes" {
  config_path = data.terraform_remote_state.rke2.outputs.kubeconfig
}
