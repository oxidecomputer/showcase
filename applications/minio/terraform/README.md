# MinIO on Oxide - Terraform module

A Terraform module that provisions the full MinIO cluster on Oxide: networking, 4 MinIO instances with local data disks, 2 LB instances with HAProxy + custom failover, 1 Floating IP, and cloud-init bootstrap of every node.

End-to-end equivalent of the manual build documented in `../minio_labguide.md`.

## Status

Under construction. Currently shipped:
- Root config skeleton
- Provider pinning (`oxidecomputer/oxide` v0.19.0)
- Project, VPC, subnet, firewall rules

To come:
- MinIO instances + local data disks + anti-affinity
- LB instances + Floating IP + anti-affinity
- Cloud-init bootstrap templates
- Two-pass MinIO cluster formation

## Prerequisites

- Terraform 1.11 or newer
- Oxide CLI installed and authenticated (`oxide auth login --host <silo-url>`)
- An Oxide silo with a linked IP pool that has free addresses
- An Ubuntu 24.04 image already uploaded to the project (block size **512**)
- A registered SSH key on your Oxide user

## Quickstart

1. Copy the example tfvars:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   $EDITOR terraform.tfvars
   ```

2. Set Oxide credentials in your shell:
   ```bash
   export OXIDE_HOST="https://<your-silo>.sys.<rack>.oxide-preview.com"
   export OXIDE_TOKEN="$(cat ~/.config/oxide/credentials.toml | awk -F'"' '/^token/{print $2}')"
   # Failover credentials, passed via env var so it never lands in tfvars/state files
   export TF_VAR_oxide_credentials_for_failover="$(cat ~/.config/oxide/credentials.toml)"
   ```

3. Initialize and plan:
   ```bash
   terraform init
   terraform plan
   ```

4. Apply:
   ```bash
   terraform apply
   ```

5. Read outputs:
   ```bash
   terraform output                                  # most things
   terraform output -raw minio_root_password         # sensitive
   ```

## Variables

See `variables.tf` for the full list. Most have sensible defaults. Required inputs:

- `ubuntu_image_id` - UUID of your Ubuntu 24.04 image
- `ssh_public_key` - your public key for ubuntu user access

## State

Local state (`terraform.tfstate`), gitignored. For production deployments, switch to a remote backend (Terraform Cloud, S3, or similar) by adding a `backend` block to `versions.tf`.

## Teardown

```bash
terraform destroy
```

Tears down everything the module created. If you set `create_project = false`, the project itself stays.

## Module structure

```
terraform/
├── main.tf              # invokes the module
├── variables.tf         # root inputs
├── outputs.tf           # root outputs
├── versions.tf          # provider pin
├── terraform.tfvars.example
├── .gitignore
└── modules/minio-on-oxide/
    ├── network.tf       # project, VPC, subnet, firewall
    ├── variables.tf     # module inputs
    ├── outputs.tf       # module outputs
    ├── locals.tf        # computed values
    └── cloud-init/      # bootstrap templates (coming)
```

## Known constraints (tracked in `../QUESTIONS-FOR-OXIDE.md`)

- **Q-ENG-9**: Local disks are hardcoded to block size 4096 in the current Oxide build. Boot disks must be `distributed` for image-sourced creation to work. Module hardcodes this; flip when the bug closes.
- **Q-ENG-10**: NVMe device numbering is not stable across instances. Cloud-init script detects the boot device dynamically.
- **Q-ENG-11**: VRRP (IP protocol 112) is dropped by Oxide VPC firewall. Module uses a TCP-polling watcher instead of keepalived.
