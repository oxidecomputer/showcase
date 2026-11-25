# Red Hat OpenShift on Oxide

A step-by-step guide for installing Red Hat OpenShift Container Platform (OCP) cluster on Oxide virtual machines. It uses the `platform: External` install type with the [Oxide Cloud Controller Manager](https://github.com/oxidecomputer/oxide-cloud-controller-manager) (CCM), so OpenShift talks to the Oxide API directly.

- PDF guide: [`ocp-on-oxide-install-guide.pdf`](ocp-on-oxide-install-guide.pdf)

---

## What you get

- 3 control plane nodes and 3 or more worker nodes, all running as Oxide instances
- The Oxide CCM (two replicas, leader-elected) initializing every node from the Oxide API, setting its provider ID (`oxide://<instance-id>`), addresses, and instance type
- Node health tracked through Oxide
- Kubernetes `Service` objects of type `LoadBalancer` turned into Oxide floating IPs automatically
- An HAProxy load balancer VM with a floating IP fronting the API (6443) and application ingress (80, 443)

---

## Validated with

| Component | Version |
|-----------|---------|
| OpenShift Container Platform | 4.20.40 |
| Oxide CLI | 0.16.0 |
| Oxide Cloud Controller Manager | 0.8.0 |
| Install method | User-provisioned infrastructure (UPI), `platform: External` |

---

## How the install works

1. Bake three Red Hat Enterprise Linux CoreOS (RHCOS) images, one per node role (bootstrap, control plane, worker). Each image carries the URL of its Ignition config.
2. Generate the Ignition configs and host them in an S3 bucket that only your rack can read.
3. Boot the bootstrap node, which runs a temporary control plane behind HAProxy.
4. Deploy the Oxide CCM. The control plane nodes boot and the CCM initializes them.
5. Remove the bootstrap node once bootstrap completes.
6. Boot the workers, approve their certificates, and let the CCM initialize them.

---

## Prerequisites

- An Oxide silo user with the collaborator role on the project (the CCM uses an API token from this user)
- An IP pool linked to the silo, for the load balancer floating IP and `LoadBalancer` services
- An Ubuntu 24.04 image in your project or silo, for the load balancer
- A Red Hat pull secret from [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret)
- An S3 bucket (AWS or any S3-compatible service with HTTPS)
- A DNS zone for the API, internal API, and application wildcard records
- Workstation tools: `openshift-install` and `oc` (same release), `oxide`, `butane`, `jq`, and `aws`

Appendix A (Optional) - To run small dnsmasq server on the load balancer when no DNS zone available for testing. 
Appendix B (Optional) - Silo using a self-signed or private-CA certificate.

---

## References

- [Oxide Cloud Controller Manager guide](https://docs.oxide.computer/guides/integrations/cloud-controller-manager)
- [Oxide Cloud Controller Manager source](https://github.com/oxidecomputer/oxide-cloud-controller-manager)
- [Oxide CLI reference](https://docs.oxide.computer/cli)
- [Red Hat: Installing a cluster with Platform External](https://docs.providers.openshift.org/platform-external/installing)
- [Ignition supported platforms](https://coreos.github.io/ignition/supported-platforms)

---

## Disclaimer

This is a reference build by an Oxide Solutions Architect Team, not an official Red Hat or Oxide product integration. Both projects are under active development, and behavior described here can change between releases.
