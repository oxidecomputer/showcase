# MinIO on Oxide

A reference build for running [MinIO](https://min.io) on the [Oxide rack](https://oxide.computer). Spin up a distributed S3-compatible object store on your own hardware in under 20 minutes with Terraform, or walk the build step by step with the lab guide.

Companion to the blog post: *Own Your Object storage with Oxide*.

---

## What you get

- A 4-node distributed MinIO cluster (16 local drives, EC:4 erasure coding, 75% storage efficiency, survives one full node loss)
- An active/standby HAProxy load balancer pair with autonomous failover (~11 second end-to-end)
- A single Floating IP fronting the cluster as the S3 endpoint
- TLS terminated at the load balancer
- Everything inside one Oxide project, one VPC, one subnet

Reference architecture and network topology diagrams are 

                                     Consuming workloads
                                              |
                                       https://s3.customer.com
                                              |
                                        +-----+-----+
                                        | Floating  |
                                        |    IP     |
                                        +-----+-----+
                                              |
                              +---------------+----------------+
                              |                                |
                       +------+--------+               +-------+-------+
                       | LB VM #1      |   keepalived  | LB VM #2      |
                       | HAProxy (TLS) | <-----------> | HAProxy (TLS) |
                       | active        |   FIP failover| standby       |
                       +------+--------+               +-------+-------+
                              |                                |
                              +---------------+----------------+
                                              |
                               +------+-------+-------+-------+
                               |      |       |       |
                          +----+--+ +-+----+ +-+----+ +-+-----+
                          | inst1 | |inst2 | |inst3 | |inst4  |
                          | MinIO | |MinIO | |MinIO | |MinIO  |
                          | local | |local | |local | |local  |
                          | [d][d]| |[d][d]| |[d][d]| |[d][d] |
                          | [d][d]| |[d][d]| |[d][d]| |[d][d] |
                          +-------+ +------+ +------+ +-------+
                               \      |        |       /
                                \     |        |      /
                                 Oxide local disks
(sled-local, no Crucible replication; MinIO EC:4 provides redundancy across drives and instances)

---

## Two paths

### Path 1: Terraform (fast)

Best for getting a working cluster up for demos, dev environments, or repeatable test rigs.

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars              # fill in image ID, SSH key, IP pool

export OXIDE_HOST="https://<your-silo>.sys.<rack>.oxide-preview.com"
export OXIDE_TOKEN="$(cat ~/.config/oxide/credentials.toml | awk -F'\"' '/^token/{print $2}')"
export TF_VAR_oxide_credentials_for_failover="$(cat ~/.config/oxide/credentials.toml)"

terraform init
terraform plan
terraform apply
```

Pull credentials and the S3 endpoint from the outputs:

```bash
terraform output -raw floating_ip
terraform output -raw minio_root_user
terraform output -raw minio_root_password   # sensitive
```

`terraform destroy` tears the whole thing down.

Full Terraform module docs in [`terraform/README.md`](terraform/README.md).

### Path 2: Manual lab guide (learn)

Best if you want to understand what each layer is doing, debug a real-world build, or document a walkthrough for your team.

The lab guide walks through every phase end to end: project setup, networking, MinIO instance provisioning, load balancer pair, Floating IP, OS bootstrap, cluster formation, watcher-based failover, and smoke testing.

- PDF version: [`MinIO_Oxide_setup_labguide.pdf`](MinIO_Oxide_setup_labguide.pdf)

About 90 minutes from "fresh silo" to "working S3 endpoint" if you follow it straight through.

---

## Prerequisites

- An Oxide silo with sufficient rights to create projects, instances, disks, VPCs, firewall rules, and Floating IPs
- At least one IP pool linked to your silo with free capacity (budget 2 pool addresses per instance for default external IP config)
- Terraform 1.11 or newer (Path 1 only)
- The [`oxide` CLI](https://github.com/oxidecomputer/oxide.rs) installed and authenticated
- An Ubuntu 24.04 LTS image uploaded to the silo (raw format, block size 512)
- A registered SSH key on your Oxide user

See the lab guide's Phase 0 for the full pre-flight checklist.

---

## Repository layout

```
.
├── README.md                          this file
├── docs/
│   ├── minio_labguide.md              step-by-step manual build (source)
│   ├── MinIO_Oxide_setup_labguide.pdf same content, distributable PDF
│   ├── ARCHITECTURE.md                why each design call was made
│   ├── reference-architecture.png     reference architecture diagram
│   └── network-architecture.png       VPC, sleds, traffic flow diagram
├── terraform/
│   ├── main.tf                        module invocation, provider config
│   ├── variables.tf                   root inputs
│   ├── outputs.tf                     credentials, endpoints, IPs
│   ├── terraform.tfvars.example       template
│   ├── README.md                      Terraform-specific docs
│   └── modules/minio-on-oxide/
│       ├── network.tf                 VPC, subnet, firewall rules
│       ├── instances-minio.tf         MinIO instances, disks, anti-affinity
│       ├── instances-lb.tf            LB instances, anti-affinity
│       ├── floating-ip.tf             FIP + attachment
│       ├── credentials.tf             generated MinIO root creds
│       └── cloud-init/                bootstrap templates
└── scripts/
    ├── bootstrap-minio.sh             idempotent MinIO node bootstrap
    ├── bootstrap-lb.sh                LB node bootstrap
    ├── minio-fip-failover.sh          idempotent FIP failover
    └── minio-lb-watcher.sh            TCP-polling watcher service
```

---

## Known constraints

Three Oxide platform quirks the build works around. Each will collapse to a cleaner pattern as Oxide ships the fix.

- **Local disks are hardcoded to block size 4096.** Image-sourced local boot disks fail to boot from the Ubuntu cloud image (GPT laid out for 512-byte sectors). Boot disks use `distributed` instead. Data disks remain local.
- **NVMe device naming is not deterministic.** The bootstrap script discovers the boot device dynamically with `findmnt` and excludes it from the data-disk format step.
- **VRRP (IP protocol 112) is dropped by the Oxide VPC firewall.** keepalived's standard heartbeat does not pass between LBs. The build uses a TCP-polling watcher script with an idempotent failover that calls the Oxide API.

---

## Default cluster sizing

| Tier | Count | vCPU | RAM | Boot disk | Data disks |
|------|-------|------|-----|-----------|------------|
| MinIO | 4 | 4 | 16 GiB | 30 GiB distributed | 4 × 100 GiB local |
| HAProxy LB | 2 | 2 | 4 GiB | 20 GiB distributed | none |

Resulting raw capacity: 1.6 TiB. Usable after EC:4: roughly 1.2 TiB. Override via `terraform.tfvars`.

---

## What this build is not

- A production-hardened deployment. TLS uses a self-signed cert by default. Root credentials sit in the MinIO env file. SSH ingress is open from `0.0.0.0/0`.
- A KMS or OIDC story. KES + Vault and customer IdP federation are explicit hardening steps, not in this repo yet.
- A multi-rack DR pattern. Single-rack deployment only.

Hardening guidance lives in the lab guide's "Tradeoffs" section.

---

## Demo video

A full walkthrough is on YouTube: [link placeholder].

The recording covers provisioning, cluster formation, a Spark workload reading and writing parquet to the MinIO endpoint, and a failover drill where lb-1 is killed and the Floating IP moves to lb-2.

---

## Companion blog

The thought-leadership post that introduces this repo and explains the design choices in plain English: [blog URL placeholder].

---

## Contributing

Issues and pull requests welcome. If you hit an Oxide platform quirk that is not yet documented or the known-constraints list above, please open an issue with the reproduction steps and any `oxide` CLI output you have. That feedback is what keeps the workarounds in the module up to date.

---

## License

Apache 2.0 unless otherwise noted. MinIO is under [GNU AGPL v3](https://github.com/minio/minio/blob/master/LICENSE).

---

## Disclaimer

This is a reference build by an Oxide solutions architect, not an official MinIO or Oxide product integration. Use at your own discretion. Both projects are under active development and platform behaviors documented here may change.
