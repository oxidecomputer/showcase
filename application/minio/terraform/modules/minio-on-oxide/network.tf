// ============================================================
// Network layer: project (optional), VPC, subnet, firewall rules.
// Smallest blast radius. Validate this with `terraform plan` first.
// ============================================================

// Project - created only if create_project = true. Otherwise reference an existing project by name via data source.
resource "oxide_project" "this" {
  count       = var.create_project ? 1 : 0
  name        = var.project_name
  description = "MinIO-on-Oxide POC (created by Terraform module)"
}

data "oxide_project" "this" {
  count = var.create_project ? 0 : 1
  name  = var.project_name
}

locals {
  project_id = var.create_project ? oxide_project.this[0].id : data.oxide_project.this[0].id
}

// VPC for the MinIO cluster
resource "oxide_vpc" "minio" {
  project_id  = local.project_id
  name        = var.vpc_name
  description = "MinIO service VPC: nodes, LB pair, Floating IP target"
  dns_name    = "minio"
}

// Subnet for all instances (MinIO + LB)
resource "oxide_vpc_subnet" "minio" {
  vpc_id      = oxide_vpc.minio.id
  name        = local.subnet_name
  description = "Subnet for MinIO nodes and LB instances"
  ipv4_block  = var.subnet_cidr
}

// Firewall rules:
// - Default rules (allow-icmp, allow-internal-inbound, allow-ssh) are recreated explicitly so we own the full ruleset.
// - allow-https-inbound opens TCP 443 for the S3 endpoint via Floating IP.
// - allow-https-console-inbound opens TCP 9443 for the MinIO Console via Floating IP.
//
// The firewall rules API replaces the entire rule set per call. TF handles that transparently.
resource "oxide_vpc_firewall_rules" "minio" {
  vpc_id = oxide_vpc.minio.id

  rules = {
    "allow-icmp" = {
      description = "allow inbound ICMP traffic from anywhere"
      priority    = 65534
      action      = "allow"
      direction   = "inbound"
      status      = "enabled"
      targets = [{
        type  = "vpc"
        value = var.vpc_name
      }]
      filters = {
        protocols = [{ type = "icmp" }]
      }
    }

    "allow-internal-inbound" = {
      description = "allow inbound traffic to all instances within the VPC if originated within the VPC"
      priority    = 65534
      action      = "allow"
      direction   = "inbound"
      status      = "enabled"
      targets = [{
        type  = "vpc"
        value = var.vpc_name
      }]
      filters = {
        hosts = [{
          type  = "vpc"
          value = var.vpc_name
        }]
      }
    }

    "allow-ssh" = {
      description = "allow inbound TCP connections on port 22 from anywhere"
      priority    = 65534
      action      = "allow"
      direction   = "inbound"
      status      = "enabled"
      targets = [{
        type  = "vpc"
        value = var.vpc_name
      }]
      filters = {
        ports     = ["22"]
        protocols = [{ type = "tcp" }]
      }
    }

    "allow-https-inbound" = {
      description = "Allow TCP 443 inbound for MinIO S3 endpoint via Floating IP"
      priority    = 100
      action      = "allow"
      direction   = "inbound"
      status      = "enabled"
      targets = [{
        type  = "vpc"
        value = var.vpc_name
      }]
      filters = {
        ports     = ["443"]
        protocols = [{ type = "tcp" }]
      }
    }

    "allow-https-console-inbound" = {
      description = "Allow TCP 9443 inbound for MinIO Console via Floating IP"
      priority    = 100
      action      = "allow"
      direction   = "inbound"
      status      = "enabled"
      targets = [{
        type  = "vpc"
        value = var.vpc_name
      }]
      filters = {
        ports     = ["9443"]
        protocols = [{ type = "tcp" }]
      }
    }
  }
}
