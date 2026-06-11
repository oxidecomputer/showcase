terraform {
  required_version = ">= 1.9"

  required_providers {
    oxide = {
      source  = "oxidecomputer/oxide"
      version = ">= 0.20.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
    }
  }
}

provider "oxide" {}
