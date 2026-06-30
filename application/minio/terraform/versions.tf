terraform {
  required_version = ">= 1.11"

  required_providers {
    oxide = {
      source  = "oxidecomputer/oxide"
      version = "= 0.19.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "oxide" {
  # Provider reads OXIDE_HOST and OXIDE_TOKEN (or OXIDE_PROFILE) from environment.
  # Do NOT hardcode here - that would put credentials in version control.
}
