# Air-Gapped OpenShift Virtualization PoC

This repository documents a Proof of Concept (PoC) for deploying **Red Hat OpenShift Container Platform in an air-gapped environment** with **OpenShift Virtualization**, using the **Agent-Based Installer**, **Bare Metal Operator / Metal³**, and KVM/libvirt-based hosts to emulate or represent bare-metal infrastructure.

The PoC focuses on a compact OpenShift cluster, disconnected image mirroring, virtual BMC integration, Day-2 configuration, shared storage, VM networking, identity management, trusted ingress certificates, and optional worker-node provisioning through the Machine API.

> **Security note**
> This repository must not contain production credentials, pull secrets, passwords, private keys, customer-sensitive data, or other secrets. Use placeholders, environment variables, or an appropriate secret-management solution instead.

---

## Table of Contents

- [Architecture](#architecture)
- [PoC Scope](#poc-scope)
- [Network Design](#network-design)
- [Prerequisites](#prerequisites)
- [Suggested Repository Structure](#suggested-repository-structure)
- [Installation Workflow](#installation-workflow)
  - [1. Prepare libvirt Networks](#1-prepare-libvirt-networks)
  - [2. Configure VLAN Interfaces](#2-configure-vlan-interfaces)
  - [3. Prepare the Local Registry](#3-prepare-the-local-registry)
  - [4. Mirror OpenShift Content](#4-mirror-openshift-content)
  - [5. Configure Virtual BMC](#5-configure-virtual-bmc)
  - [6. Create Installer Configuration](#6-create-installer-configuration)
  - [7. Generate the Agent ISO](#7-generate-the-agent-iso)
  - [8. Install OpenShift](#8-install-openshift)
- [Day-2 Configuration](#day-2-configuration)
  - [DNS and Cluster Access](#dns-and-cluster-access)
  - [OpenShift Virtualization](#openshift-virtualization)
  - [Shared Storage](#shared-storage)
  - [KubeVirt Networks](#kubevirt-networks)
  - [Identity Provider](#identity-provider)
  - [Trusted Ingress Certificate](#trusted-ingress-certificate)
- [Optional Worker Node Provisioning](#optional-worker-node-provisioning)
- [Validation and Troubleshooting](#validation-and-troubleshooting)
- [Important Notes](#important-notes)

---

## Architecture

The PoC uses a **three-node compact OpenShift cluster**, where each initial node provides both control-plane and worker functionality.

| Component | Value |
|---|---|
| Cluster topology | 3-node compact cluster |
| Installation method | Agent-Based Installer |
| Infrastructure integration | Bare Metal Operator / Metal³ |
| Hypervisor | KVM/libvirt on RHEL 9 |
| API VIP | `192.168.60.10` |
| Ingress VIP | `192.168.60.20` |
| Node 1 | `192.168.60.11` — rendezvous host |
| Node 2 | `192.168.60.12` |
| Node 3 | `192.168.60.13` |
| Optional workers | Node 4 and Node 5 |

The installation flow is based on standard OpenShift inputs such as the cluster name, base domain, pull secret, SSH key, infrastructure settings, and node configuration. These are processed through `install-config.yaml` and the Agent-Based Installer to generate the bootable installation media and machine configuration required by the target nodes.

---

## PoC Scope

This repository covers the following areas:

- Air-gapped OpenShift installation
- Disconnected image mirroring with `oc-mirror`
- Local TLS-enabled container registry
- KVM/libvirt network preparation
- VLAN-based machine and VM networking
- Agent-Based Installer configuration
- Bare Metal Operator / Metal³ integration
- Virtual BMC for KVM-backed hosts
- OpenShift Virtualization installation
- NFS and NetApp/Trident shared storage examples
- KubeVirt secondary networks using NNCP and NAD resources
- `htpasswd` identity-provider configuration
- Custom ingress certificates
- Optional Day-2 worker provisioning with BareMetalHost and MachineSet resources

This is a **Proof of Concept**, not a production reference architecture. Network ranges, certificates, passwords, hostnames, storage backends, resource sizes, and security settings must be reviewed before reuse.

---

## Network Design

Three libvirt networks are used.

| Network | Purpose | Example |
|---|---|---|
| `ocp-net` | OpenShift machine/install network | VLAN 40 / `192.168.60.0/24` |
| `vtn-net` | Network for virtual machine traffic | VLAN 100 / `192.168.70.0/24` |
| `provisioning-net` | Bare Metal Operator / Metal³ provisioning | `172.22.0.0/24` |

Each OpenShift node is attached to the required libvirt networks. The compact cluster nodes use multiple `ocp-net` interfaces plus dedicated `vtn-net` and `provisioning-net` interfaces.

### Expected libvirt Networks

```bash
virsh net-list --all
```

Expected result:

```text
ocp-net            active   yes   yes
provisioning-net   active   yes   yes
vtn-net            active   yes   yes
```

---

## Prerequisites

The PoC assumes the following components are available:

- RHEL 9 KVM/libvirt host
- Three prepared OpenShift node VMs
- Optional VM shells for additional workers
- `virsh`
- `nmcli`
- `podman`
- `oc`
- `openshift-install`
- `oc-mirror`
- `jq`
- `curl`
- `ipmitool`
- Python 3
- `virtualbmc`
- `httpd-tools` for `htpasswd`
- DNS resolution for the OpenShift API and application wildcard domain
- Red Hat pull secret for disconnected mirroring
- Sufficient local storage for mirrored images and workspace data

The examples use a working directory similar to:

```text
/var/poc-polizei
```

For reuse, it is recommended to replace this path with a customer-neutral project directory such as:

```text
/var/ocp-airgap-poc
```

---

## Suggested Repository Structure

The source material references a number of YAML, XML, and shell files. A clean repository layout could look like this:

```text
.
├── README.md
├── network/
│   ├── ocp-net.xml
│   ├── vm-net.xml
│   └── provisioning-net.xml
├── installer/
│   ├── install-config.yaml.example
│   ├── agent-config.yaml.example
│   ├── imageset-config.yaml.example
│   ├── cleanup-installer.sh
│   └── install-iso-file.sh
├── registry/
│   └── README.md
└── day2/
    ├── nfs-provisioner.yaml
    ├── nfs-deployment.yaml
    ├── trident-secret.yaml.example
    ├── trident-backend-config.yaml.example
    ├── trident-storage-class.yaml
    ├── nncp-vlan40.yaml
    ├── nad-vlan40.yaml
    ├── bmc-secrets.yaml.example
    ├── provisioning-configuration.yaml
    ├── baremetalhosts.yaml
    ├── worker-machineset.yaml
    ├── cluster-issuer.yaml
    └── ingress-wildcard-certificate.yaml
```

Files containing credentials should be committed only as sanitized `.example` templates.

---

# Installation Workflow

## 1. Prepare libvirt Networks

Define and activate the required libvirt networks.

### OpenShift machine network

```bash
virsh net-define ./network/ocp-net.xml
virsh net-start ocp-net
virsh net-autostart ocp-net
```

### VM network

```bash
virsh net-define ./network/vm-net.xml
virsh net-start vtn-net
virsh net-autostart vtn-net
```

### Provisioning network

```bash
virsh net-define ./network/provisioning-net.xml
virsh net-start provisioning-net
virsh net-autostart provisioning-net
```

Attach the required interfaces to all cluster nodes and verify them with:

```bash
virsh domiflist ocp4-node1
virsh domiflist ocp4-node2
virsh domiflist ocp4-node3
```

A compact overview can be generated with:

```bash
for node in ocp4-node1 ocp4-node2 ocp4-node3 ocp4-node4 ocp4-node5; do
  echo "------------"
  virsh domiflist "$node" | \
    awk -v n="$node" '/ocp-net|provisioning-net|vtn-net/ {
      printf "%-12s | %-18s | %s\n", n, $3, $5
    }'
done
```

---

## 2. Configure VLAN Interfaces

The PoC uses tagged VLAN interfaces on top of the libvirt bridges so that the host and libvirt `dnsmasq` can correctly handle traffic for the OpenShift machine and VM networks.

### VLAN 40 — OpenShift machine network

```bash
nmcli connection add type vlan \
  con-name virbr1.40 \
  ifname virbr1.40 \
  dev virbr1 \
  id 40 \
  ipv4.method manual \
  ipv4.addresses 192.168.60.1/32 \
  connection.zone trusted
```

Add the required host routes:

```bash
nmcli connection modify virbr1.40 \
  +ipv4.routes "192.168.60.10/32, 192.168.60.11/32, 192.168.60.12/32, 192.168.60.13/32, 192.168.60.14/32, 192.168.60.15/32, 192.168.60.20/32"

nmcli connection up virbr1.40
```

The corresponding libvirt network can bind `dnsmasq` to the VLAN interface:

```xml
<network xmlns:dnsmasq="http://libvirt.org/schemas/network/dnsmasq/1.0">
  <dnsmasq:options>
    <dnsmasq:option value="interface=virbr1.40"/>
  </dnsmasq:options>
</network>
```

### VLAN 100 — VM network

```bash
nmcli connection add type vlan \
  con-name virbr2.100 \
  ifname virbr2.100 \
  dev virbr2 \
  id 100 \
  ipv4.method manual \
  ipv4.addresses 192.168.70.1/32 \
  connection.zone trusted

nmcli connection modify virbr2.100 \
  +ipv4.routes "192.168.70.11/32, 192.168.70.12/32, 192.168.70.13/32, 192.168.70.14/32, 192.168.70.15/32"

nmcli connection up virbr2.100
```

---

## 3. Prepare the Local Registry

Create the working directories:

```bash
mkdir -p /var/ocp-airgap-poc/{certs,data,metadata,workspace}
cd /var/ocp-airgap-poc
```

Create a TLS certificate for the local registry. Replace the hostname and IP address with values appropriate for the target environment.

```bash
openssl req -newkey rsa:4096 -nodes -sha256 \
  -keyout certs/domain.key \
  -x509 -days 365 \
  -out certs/domain.crt \
  -subj "/CN=<registry-hostname>" \
  -addext "subjectAltName=DNS:<registry-hostname>,IP:<registry-ip>"
```

Run the registry:

```bash
podman run -d \
  --name local-registry \
  --restart=always \
  -p 5000:5000 \
  -v /var/ocp-airgap-poc/data:/var/lib/registry:z \
  -v /var/ocp-airgap-poc/certs:/certs:z \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  docker.io/library/registry:2
```

For fully disconnected environments, export the registry container image on a connected system and import it into the air-gapped environment before starting the registry.

---

## 4. Mirror OpenShift Content

Create an authentication file containing the Red Hat pull secret and required registry credentials.

```bash
printf '%s\n' '<PULL_SECRET_JSON>' > /var/ocp-airgap-poc/auth.json
```

Authenticate to the required registries:

```bash
podman login registry.redhat.io --authfile /var/ocp-airgap-poc/auth.json
podman login quay.io --authfile /var/ocp-airgap-poc/auth.json
podman login <registry-hostname>:5000 \
  --tls-verify=false \
  --authfile /var/ocp-airgap-poc/auth.json
```

Install `oc-mirror` on the connected system and define the required content in `imageset-config.yaml`.

Example mirroring command:

```bash
oc-mirror \
  -c /var/ocp-airgap-poc/imageset-config.yaml \
  --workspace file:///var/ocp-airgap-poc/workspace \
  --authfile /var/ocp-airgap-poc/auth.json \
  --dest-tls-verify=false \
  docker://<registry-hostname>:5000/openshift/release \
  --v2
```

For subsequent synchronization runs, retry and parallelization parameters can be added:

```bash
oc-mirror \
  -c /var/ocp-airgap-poc/imageset-config.yaml \
  --workspace file:///var/ocp-airgap-poc/workspace \
  --authfile /var/ocp-airgap-poc/auth.json \
  --dest-tls-verify=false \
  --retry-times 10 \
  --parallel-images 2 \
  --parallel-layers 2 \
  docker://<registry-hostname>:5000/openshift/release \
  --v2
```

Validate the registry:

```bash
curl -k https://<registry-hostname>:5000/v2/_catalog | jq .
```

Check the mirrored OpenShift release before installation:

```bash
oc adm release info \
  <registry-hostname>:5000/openshift/release/openshift/release-images:<version>-x86_64 \
  --insecure=true
```

---

## 5. Configure Virtual BMC

For a KVM-based PoC, VirtualBMC can expose IPMI-compatible BMC endpoints for the libvirt VMs.

```bash
python3 -m venv /opt/vbmc --system-site-packages
source /opt/vbmc/bin/activate
pip install virtualbmc
```

After configuring the `vbmcd` systemd service, register the OpenShift nodes.

Example:

```bash
vbmc add ocp4-node1 \
  --address <bmc-host-ip> \
  --port 6234 \
  --libvirt-uri qemu:///system \
  --username <bmc-user> \
  --password '<bmc-password>'

vbmc start ocp4-node1
vbmc list
```

Validate the IPMI endpoint:

```bash
ipmitool -I lanplus \
  -H <bmc-host-ip> \
  -U <bmc-user> \
  -P '<bmc-password>' \
  -p 6234 \
  power status
```

---

## 6. Create Installer Configuration

The installer uses two main configuration files:

- `install-config.yaml`
- `agent-config.yaml`

Typical variables used to generate these files include:

```bash
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub)
REGISTRY_CA=$(cat /var/ocp-airgap-poc/certs/domain.crt)
PULL_SECRET=$(tr -d '\n' < /var/ocp-airgap-poc/auth.json)
```

The disconnected registry configuration must ensure that release and operator images are resolved exclusively through the internal mirror where required.

Keep real credentials outside Git and commit only sanitized templates.

---

## 7. Generate the Agent ISO

Before creating a new installation image, remove stale installer artifacts and prepare fresh copies of the configuration files.

The PoC uses helper scripts for this process:

```bash
./cleanup-installer.sh
./install-iso-file.sh
```

The resulting ISO is used to boot all three compact-cluster nodes.

---

## 8. Install OpenShift

Boot the three prepared KVM nodes from the generated Agent-Based Installer ISO.

Monitor bootstrap completion:

```bash
openshift-install agent wait-for bootstrap-complete \
  --dir=/var/ocp-airgap-poc/installer \
  --log-level=info
```

Follow the installer log:

```bash
tail -f /var/ocp-airgap-poc/installer/.openshift_install.log
```

Useful node-side logs include:

```bash
journalctl -f -u agent-installer
journalctl -f -u agent-bootstrapper -u assisted-service
sudo systemctl list-units --failed
```

---

# Day-2 Configuration

## DNS and Cluster Access

Verify API and application DNS resolution:

```bash
dig @<dns-server> api.<cluster>.<base-domain> +short
dig @<dns-server> console-openshift-console.apps.<cluster>.<base-domain> +short
```

Export the cluster kubeconfig:

```bash
export KUBECONFIG=/var/ocp-airgap-poc/installer/auth/kubeconfig
```

---

## OpenShift Virtualization

Install the **OpenShift Virtualization Operator** through OperatorHub and verify that the operator installation completes successfully.

---

## Shared Storage

### NFS Example

Create and export an NFS directory on the infrastructure host:

```bash
mkdir -p /var/nfs/ocp-pv1
chmod 777 /var/nfs/ocp-pv1
```

Apply the NFS provisioner resources:

```bash
oc apply -f day2/nfs-provisioner.yaml
oc apply -f day2/nfs-deployment.yaml
```

If required by the PoC provisioner:

```bash
oc adm policy add-scc-to-user hostmount-anyuid \
  -z nfs-client-provisioner \
  -n nfs-provisioner
```

### NetApp / Trident Example

The PoC also demonstrates shared storage through Astra Trident using an ONTAP NAS backend.

Typical resources include:

```bash
oc apply -f day2/trident-secret.yaml
oc apply -f day2/trident-backend-config.yaml
oc apply -f day2/trident-storage-class.yaml
```

All backend addresses and credentials must be supplied through environment-specific configuration and Kubernetes Secrets.

---

## KubeVirt Networks

Two VM network concepts are included:

1. **External VM network** using an NNCP and NAD with a tagged VLAN.
2. **Internal east-west VM network** using a dedicated NAD.

Example resources:

```text
day2/nncp-vlan40.yaml
day2/nad-vlan40.yaml
```

The exact VLAN ID and subnet must be adapted to the target environment.

---

## Identity Provider

Install the `htpasswd` utility:

```bash
dnf install -y httpd-tools
```

Create the password file outside the Git repository and create the OpenShift secret:

```bash
oc create secret generic htpasswd-secret \
  --from-file=htpasswd=/secure/path/htpasswd \
  -n openshift-config
```

Configure the OAuth resource to use the `htpasswd` identity provider and assign RBAC roles as required.

Example:

```bash
oc adm policy add-cluster-role-to-user cluster-admin <user>
```

Use least-privilege permissions in production environments.

---

## Trusted Ingress Certificate

The PoC replaces the default ingress certificate using `cert-manager`.

High-level flow:

1. Install the cert-manager Operator.
2. Create a CA / `ClusterIssuer`.
3. Request a wildcard certificate for the OpenShift application domain.
4. Patch the default ingress controller to use the new TLS secret.
5. Add the CA to the cluster-wide trusted CA bundle where required.
6. Import the CA into administrative clients or enterprise trust stores.

Example ingress-controller patch:

```bash
oc patch ingresscontroller default \
  -n openshift-ingress-operator \
  --type=merge \
  -p '{"spec":{"defaultCertificate":{"name":"apps-wildcard-tls"}}}'
```

Monitor rollout:

```bash
oc rollout status deployment/router-default -n openshift-ingress
```

---

# Optional Worker Node Provisioning

The PoC can be extended with additional workers managed through the OpenShift Machine API and Bare Metal Operator.

The general workflow is:

1. Prepare powered-off VM shells for the additional workers.
2. Attach blank disks and all required network interfaces.
3. Register the worker VMs with the BMC emulation layer.
4. Create BMC credential Secrets.
5. Configure the Metal³ provisioning network.
6. Create the `BareMetalHost` resources.
7. Apply the worker `MachineSet`.
8. Scale the `MachineSet`.
9. Monitor BareMetalHost, Machine, CSR, and node state.

Example provisioning-network settings:

```yaml
spec:
  provisioningNetwork: Managed
  provisioningInterface: <provisioning-interface>
  provisioningIP: 172.22.0.3
  provisioningNetworkCIDR: 172.22.0.0/24
  provisioningDHCPRange: 172.22.0.10,172.22.0.100
  preProvisioningOSDownloadURLs: {}
  watchAllNamespaces: true
```

Apply the resources:

```bash
oc apply -f day2/bmc-secrets.yaml
oc apply -f day2/provisioning-configuration.yaml
oc apply -f day2/baremetalhosts.yaml
oc apply -f day2/worker-machineset.yaml
```

Scale the worker MachineSet:

```bash
oc scale machineset <machineset-name> \
  -n openshift-machine-api \
  --replicas=2
```

Monitor progress:

```bash
oc get bmh -n openshift-machine-api
oc get machines -n openshift-machine-api
oc get nodes
oc get csr
```

Approve pending CSRs only after validating that they belong to the expected joining nodes.

---

# Validation and Troubleshooting

### Registry

```bash
curl -vk https://<registry-hostname>:5000
curl -k https://<registry-hostname>:5000/v2/_catalog | jq .
```

### libvirt networks

```bash
virsh net-list --all
```

### Interface overview

```bash
for node in ocp4-node1 ocp4-node2 ocp4-node3; do
  echo "=== $node ==="
  virsh domiflist "$node"
done
```

### Network packet debugging

```bash
tcpdump -nn -i any \
  "host (<host-ip> or <node-ip>) and (port 53 or port 5000 or icmp or port 22)"
```

### Metal³ / Bare Metal Operator

```bash
oc get pods -n openshift-machine-api | grep -E 'metal3|baremetal|ironic'
oc get bmh -n openshift-machine-api
```

### Cluster machines and nodes

```bash
oc get machines -n openshift-machine-api
oc get nodes -o wide
```

---

# Important Notes

- The IP addresses, VLAN IDs, DNS names, storage endpoints, MAC addresses, and file paths shown here are PoC examples and must be adapted before reuse.
- Do not commit Red Hat pull secrets, BMC credentials, registry credentials, private keys, `htpasswd` files, NetApp credentials, or generated kubeconfig/auth files.
- Prefer trusted certificates in customer environments instead of disabling TLS verification.
- `chmod 777`, `no_root_squash`, self-signed certificates, and broad `cluster-admin` grants are acceptable only where explicitly approved for a PoC. They should be replaced with production-grade controls for real deployments.
- Validate the supported OpenShift version and corresponding RHCOS artifacts before mirroring or installation.
- Keep the disconnected mirror workspace and generated metadata available for later synchronization or update operations.

---

## References

For production deployments, always validate the PoC procedure against the official Red Hat OpenShift documentation for the exact OpenShift release in use, especially for:

- Agent-Based Installer
- Disconnected installation and `oc-mirror`
- Bare Metal Operator / Metal³
- OpenShift Virtualization
- NMState / NetworkAttachmentDefinition
- Machine API
- Ingress certificate replacement
- Identity-provider configuration

