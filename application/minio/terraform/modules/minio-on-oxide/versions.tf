// Provider declaration for the module. Required so Terraform knows that
// `oxide_*` resources come from oxidecomputer/oxide, not hashicorp/oxide.
// Version constraint matches the root's pin.

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
