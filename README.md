# Airgapped Environment OpenShift PoC

> **Private repository / dedicated PoC environment**
>
> This README is a Markdown representation of the original PoC document we created to the PoC in Berlin.
> The original wording, explanations, environment values and commands are "partially" intentionally retained.
> The PoC working directory used throughout this README is **`/var/ocp-airgap-poc`**. This is a private Repository.


---

## Table of Contents

1. [Overview](#overview)
2. [Network stuff in KVM](#network-stuff-in-kvm)
3. [Overview Install Process of OpenShift](#overview-install-process-of-openshift)
4. [Local Registry for Airgapped Installation](#local-registry-for-airgapped-installation)
5. [VirtualBMC](#virtualbmc)
6. [Create env & files for the Metal3 Installer](#create-env--files-for-the-metal3-installer)
7. [Installing OpenShift](#installing-openshift)
8. [After the Installation - Day2](#after-the-installation---day2)
9. [Additional Worker Nodes (Optional!)](#additional-worker-nodes-optional)

---

# Overview

Purpose of this GitHub Repository:
This repository serves as a general Proof of Concept (PoC) for an OpenShift Virtualization
deployment on bare-metal infrastructure.

The deployment is executed using the Bare Metal Operator and the Agent-Based Installer
approach. This method combines the user-friendly workflow of the Assisted
Installer—commonly known from cloud environments—with the control of an
Infrastructure-Provisioned Infrastructure (IPI) deployment. By integrating with the hardware
layer via BMC (specifically the iDRAC interface in our setup), the system is aware of the
underlying physical infrastructure, enabling dynamic provisioning and seamless scaling of
additional worker nodes.

Note: Of course - although this is a private repository, it contains no credentials, secrets, or
sensitive customer data.

Fedora Root Acces:
```text
#storm4 (Alias for ssh access to my Remote Bastion Host)
```

Directory: Image Location on Storm4 for libvirt Images!
/var/lib/libvirt/images

Directory: Location for everything which we need for the PoC!
/var/ocp-airgap-poc

# Network stuff in KVM

## Create the 3 libvirt nets

### OpenShift Machine Network

```text
#virsh net-define /var/ocp-airgap-poc/ocp-net.xml
#virsh net-start ocp-net
#virsh net-autostart ocp-net
```

### VM-Network

```text
##virsh net-define /var/ocp-airgap-poc/vm-net.xml
#virsh net-start vtn-net
#virsh net-autostart vtn-net
```

### Provisioning-Network (Day2 Directory!)

```text
#virsh net-define /var/ocp-airgap-poc/day2/provisioning-net.xmlvirt-net.xml
#virsh net-start vtn-net
#virsh net-autostart vtn-net
```

Delete a network! (Detach the Interfaces afterwards manually…
```text
#virsh net-destroy ocp-net 2>/dev/null
#virsh net-undefine ocp-net 2>/dev/null
```

And new again……
```text
#virsh net-define /var/ocp-airgap-poc/ocp-net.xml
#virsh net-start ocp-net
#virsh net-autostart ocp-net
```

## Attach Interfaces for all 3 libvirt networks!

Hybrid Nodes (Compact Cluster Nodes, Control Plane & Worker)
The MAC addresses we got from the VM Configuration!
Example for the virsh attach-interface
```text
#virsh attach-interface --domain ocp4-node1 --type network --source provisioning-net --model
virtio --mac 52:54:00:02:2d:fd --config --live
#virsh attach-interface --domain ocp4-node2 --type network --source provisioning-net --model
virtio --mac 52:54:00:fb:3e:4b --config --live
#virsh attach-interface --domain ocp4-node3 --type network --source provisioning-net --model
virtio --mac 52:54:00:62:ba:2c --config --live
```

Two additional Worker Nodes (Optional)
```text
#virsh attach-interface --domain ocp4-node4 --type network --source provisioning-net --model
virtio --mac 52:54:00:b2:03:ce --config
#virsh attach-interface --domain ocp4-node5 --type network --source provisioning-net --model
virtio --mac 52:54:00:c9:c6:76 --config
```

Do the same for the 2 other libvert network, vm-net and ocp-net (two interfaces!)

In the case - we have to detach these interfaces again:
Figure out the MAC addresses:
```text
#virsh domiflist ocp4-node1
#virsh domiflist ocp4-node2
#virsh domiflist ocp4-node3
#virsh domiflist ocp4-node4 (reserved worker node!)
#virsh domiflist ocp4-node5 (reserved worker node!)
```

Or do just:
```text
#for node in ocp4-node1 ocp4-node2 ocp4-node3 ocp4-node4 ocp4-node5; do
  echo "------------"
  virsh domiflist $node | awk -v n="$node" '/ocp-net|provisioning-net|vtn-net/ {printf "%-12s |
%-18s | %s\n", n, $3, $5}'
done; echo "------------"
```

Remove the Interfaces (example):
```text
#virsh detach-interface --domain ocp4-node1 --type network --mac 52:54:00:d4:2a:a5
--config --live
#virsh detach-interface --domain ocp4-node2 --type network --mac 52:54:00:38:d2:10
--config --live
```

```text
#virsh detach-interface --domain ocp4-node3 --type network --mac 52:54:00:83:ff:f7 --config
--live
```

## Now, we should have 3 libvirt nets

Net1: ocp-net                   (install / machine network for LACP Install!)
Net2: vtn-net                  (install / for virtual machines)
Net3: provisioning-net           (BMH / Metal3, OpenShift)

## Network Node Config (virsh)

```text
# virsh domiflist --domain ocp4-node1
 Interface Type            Source              Model MAC
----------------------------------------------------------------------
 network                   ocp-net             virtio 52:54:00:aa:bb:01
 network                   ocp-net             virtio 52:54:00:aa:bb:21
 network                   vtn-net             virtio 52:54:00:5c:b6:a3
 network                   provisioning-net    virtio 52:54:00:02:2d:fd
```

```text
# virsh domiflist --domain ocp4-node2
 Interface Type            Source              Model MAC
----------------------------------------------------------------------
 network                   ocp-net             virtio 52:54:00:aa:bb:02
 network                   ocp-net             virtio 52:54:00:aa:bb:22
 network                   vtn-net             virtio 52:54:00:ab:fe:cb
 network                   provisioning-net    virtio 52:54:00:fb:3e:4b
```

```text
# virsh domiflist --domain ocp4-node3
 Interface Type            Source              Model MAC
----------------------------------------------------------------------
 network                   ocp-net             virtio 52:54:00:aa:bb:03
 network                   ocp-net             virtio 52:54:00:aa:bb:23
 network                   vtn-net             virtio 52:54:00:64:e5:9d
 network                   provisioning-net    virtio 52:54:00:62:ba:2c
```

```text
# virsh domiflist --domain ocp4-node4 (Optional, this node is not there yet!)
 Interface Type            Source              Model MAC
----------------------------------------------------------------------
 network                   ocp-net             virtio 52:54:00:01:c6:89
 network                   ocp-net             virtio 52:54:00:aa:bb:24
 network                   vtn-net             virtio 52:54:00:db:03:17
 network                   provisioning-net    virtio 52:54:00:b2:03:ce

#virsh domiflist --domain ocp4-node5 (Optional, this node is not there yet!)
 Interface Type            Source              Model MAC
----------------------------------------------------------------------
 network                   ocp-net             virtio 52:54:00:dd:ed:70
 network                   ocp-net             virtio 52:54:00:aa:bb:25
 network                   vtn-net             virtio 52:54:00:d4:b4:1c
 network                   provisioning-net    virtio 52:54:00:c9:c6:76

Fast Check for all nodes in regards of ALL, incl. the two install leg interfaces (the later bond
interface in OpenShift:
```text
#for node in ocp4-node1 ocp4-node2 ocp4-node3 ocp4-node4 ocp4-node5; do echo "===
Schnittstellen für $node ==="; virsh domiflist $node | grep -E
"ocp-net|provisioning-net|vtn-net"; echo ""; done
```

Fast Check for all MAC Addresses on the VM’s
```text
#for node in ocp4-node1 ocp4-node2 ocp4-node3 ocp4-node4 ocp4-node5; do
 echo "------------"
 virsh domiflist $node | awk -v n="$node" '/ocp-net|provisioning-net|vtn-net/ {printf "%-12s |
%-18s | %s\n", n, $3, $5}'
done; echo "------------"
```

Status Check all Networks in KVM
```text
#virsh net-list --all
```

Expected Outcome:
ocp-net               active yes        yes
provisioning-net      active yes        yes
vtn-net               active yes        yes

## Create Network Bond with VLAN ovp-net & vtn-net

To enable OpenShift nodes in the PoC to communicate across tagged VLANs on a Linux
hypervisor we configure the host network and the hypervisor’s (KVM/libvirt) built-in
DHCP/DNS service to recognize VLAN traffic.

First, we create a tagged VLAN sub-interface (virbr1.40) on top of our existing virtual
bridge (virbr1) and assign the host IP address (192.168.60.1). Because this sub-interface
uses a single-host mask, we add explicit static routes telling the host OS that traffic destined
for our OpenShift nodes and API endpoints (.10 through .15 and .20) must travel through this
specific VLAN 40 path.

Finally - because libvirt's embedded DHCP and DNS server (dnsmasq) only listens on base
bridge interfaces by default, we update the virtual network XML file (ocp-net.xml and
vm-net.xml) to explicitly bind dnsmasq to our new VLAN sub-interfaces (virbr1.40 for the
machine network and virbr2.100 for the VM Network). This ensures that when virtual
machines boot up and request IP addresses over tagged VLAN traffic, dnsmasq captures
those requests and hands out the proper DHCP leases.

### VLAN40 - ocp-net (virbr1.40)

```text
# Create the VLAN 40 profile with link-local IP
nmcli connection add type vlan con-name virbr1.40 ifname virbr1.40 dev virbr1 id 40
ipv4.method manual ipv4.addresses 192.168.60.1/32 connection.zone trusted
```

```text
# Add the persistent host routes (including .14 and .15)
nmcli connection modify virbr1.40 +ipv4.routes "192.168.60.11/32, 192.168.60.12/32,
192.168.60.13/32, 192.168.60.14/32, 192.168.60.15/32, 192.168.60.10/32,
192.168.60.20/32"
```

```text
# Bring the interface up
nmcli connection up virbr1.40
```

And add that in the ocp-net.xml File for the libvirt Net:
```text
<network xmlns:dnsmasq='http://libvirt.org/schemas/network/dnsmasq/1.0'>
 <dnsmasq:options>
  <dnsmasq:option value="interface=virbr1.40"/>
 </dnsmasq:options>
</network>
```

### VLAN100 - vtn-net

```text
# Create the VLAN 100 profile with link-local IP
nmcli connection add type vlan con-name virbr2.100 ifname virbr2.100 dev virbr2 id 100
ipv4.method manual ipv4.addresses 192.168.70.1/32 connection.zone trusted
```

```text
# Add the persistent host routes (including .14 and .15)
nmcli connection modify virbr2.100 +ipv4.routes "192.168.70.11/32, 192.168.70.12/32,
192.168.70.13/32, 192.168.70.14/32, 192.168.70.15/32"
```

```text
# Bring the interface up
nmcli connection up virbr2.100
```

And add that in the ocp-net.xml File for the libvirt Net:
```text
<network xmlns:dnsmasq='http://libvirt.org/schemas/network/dnsmasq/1.0'>
 <dnsmasq:options>
  <dnsmasq:option value="interface=virbr2.100"/>
 </dnsmasq:options>
</network>
```

Optional: To delete the connections again
```text
#nmcli connection delete virbr1.40 2>/dev/null
#nmcli connection delete virbr2.100 2>/dev/null
```

--------------------------------------------------------------------------------------------------
Bit of Troubleshoooting….
```text
#tcpdump -nn -i any "host (192.168.60.1 or 192.168.60.11) and (port 53 or port 5000 or icmp
or port 22)"
```

# Overview Install Process of OpenShift

## Architectural Summary

- Nodes:                       3 Compact Nodes (Master + Worker role combined)
- Ingress Virtual IPs (VIPs):  192.168.60.20
- API VIP:                     192.168.60.10
- Node IPs:
           - ocp4-node1.pb-poc.ocp.polizei.test: 192.168.60.11 (Rendezvous Host!!)
           - ocp4-node2.pb-poc.ocp.polizei.test: 192.168.60.12
           - ocp4-node3.pb-poc.ocp.polizei.test: 192.168.60.13

## Design Picture / Architecture

### 1. Input Dependencies (Configuration Fields)

The configuration data is divided into three distinct functional categories:

- Core configuration files required for any OpenShift cluster, which include:
  - Cluster name (the unique identifier for the cluster, e.g., cluster1)
  - Base domain (the DNS domain for routing, e.g., companyname.com)
  - Pull secret (for authenticating against Red Hat registries)
  - SSH key (the public key of the administrator used for troubleshooting access)

- Infrastructure-specific configuration containing details about:
  - Platform (the underlying virtualization provider or bare-metal environment)

  - Platform info (infrastructure-specific access credentials)

- Advanced configurations for tuning the environment:
  - Node configuration (defining machine pools, specific settings for control plane,
            and compute nodes)

### 2. The Processing Engine (install-config.yaml)

These inputs are aggregated and processed through two primary stages:
   1. install-config.yaml: This is the master configuration file where all the dependencies
       mentioned above are defined and declared.
   2. Ignition: The installation utility consumes the install-config.yaml file to generate
       low-level machine-readable boot configuration files (called Ignition files).

### 3. Installation Targets

During the host boot phase, the Ignition configuration is consumed to provision and configure
the targeted cluster hosts. These target nodes are categorized into three roles:

- Bootstrap node: A temporary node configured to orchestrate the cluster initialization.
      It hosts a temporary Kubernetes API server to build the permanent control plane and
      is destroyed once the installation finishes.
- Control plane (Master nodes): Highly available nodes running Kubernetes
      control-plane components (such as API-server, controllers, schedulers) and the etcd
      state database.
- Compute nodes (Worker nodes): Nodes responsible for running actual user
      applications and workloads.

# Local Registry for Airgapped Installation

## TLS Certs Registry

### Working dir on Storm4

```text
#mkdir -p /var/ocp-airgap-poc/{certs,data,metadata,workspace}
#cd /var/ocp-airgap-poc
```

### TLS-Certs for local Registry

```text
#openssl req -newkey rsa:4096 -nodes -sha256 \ -keyout /var/ocp-airgap-poc/certs/domain.key \
-x509 -days 365 \ -out /var/ocp-airgap-poc/certs/domain.crt \ -subj "/CN=storm4.ocp.polizei.test" \
-addext "subjectAltName=DNS:storm4.ocp.polizei.test,IP:192.168.60.1"
```

## Podman Registry

### Start Podman Cocker Registry

Image we need:
```text
#podman inspect docker.io/library/registry:2 --format '{{.RepoTags}} {{.Digest}}'
```

Test it:
```text
podman run --rm --entrypoint echo -p 5000:5000 -v /var/ocp-airgap-poc/data:/var/lib/registry:z
-v /var/ocp-airgap-poc/certs:/certs:z -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt
-e REGISTRY_HTTP_TLS_KEY=/certs/domain.key docker.io/library/registry:2 "Syntax and
flags are valid!"
```

Run it!
```text
#podman run -d --name local-registry --restart=always -p 5000:5000 -v
/var/ocp-airgap-poc/data:/var/lib/registry:z -v /var/ocp-airgap-poc/certs:/certs:z -e
REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt -e
REGISTRY_HTTP_TLS_KEY=/certs/domain.key docker.io/library/registry:2
```

### Take the docker.io/library/registry:2 offline

Download the Registry Image & save it
```text
#sudo podman pull docker.io/library/registry:2
#sudo podman tag docker.io/library/registry:2 local-poc-registry:2
#sudo podman save -o /var/ocp-airgap-poc/harddisk-test/registry-image.tar local-poc-registry:2
```

Load the Image in the air-gapped env
```text
#sudo podman load -i /var/ocp-airgap-poc/harddisk-test/registry-image.tar
```

You might inspect the registry now, is now “local” - ignore the docker.io address….
```text
#sudo podman inspect local-poc-registry:2
```

Start Container Image/Registry airgapped!
```text
#podman run -d --name local-registry --restart=always -p 5000:5000 -v
/var/ocp-airgap-poc/data:/var/lib/registry:z -v /var/ocp-airgap-poc/certs:/certs:z -e
REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt -e
REGISTRY_HTTP_TLS_KEY=/certs/domain.key local-poc-registry:2
```

## Mirror offline & oc-mirror for images

Authfile (pull-secret,RH registry, Podman Registry):
```text
#echo '{}' > /var/ocp-airgap-poc/auth.json // Create auth file with an empty json object!
```

### Login Registry in auth.json

```text
# Mein Pull Secret in Auth File einfügen:
```

```text
printf '%s\n' '{PULL_SECRET}' > /var/ocp-airgap-poc/auth.json
```

```text
# Red Hat Registry Login
podman login registry.redhat.io --authfile /var/ocp-airgap-poc/auth.json
```

```text
# Quay.io Release Login (wird für das Release-Image benötigt)
podman login quay.io --authfile /var/ocp-airgap-poc/auth.json
```

```text
# Login polizei Registry: - give auth file to local Registry:
podman login storm4.ocp.polizei.test:5000 --tls-verify=false --authfile
/var/ocp-airgap-poc/auth.json
```

### oc-mirror Binary installieren

```text
#curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/oc-mirror.tar.gz && tar
-xzf oc-mirror.tar.gz -C /usr/local/bin/ && chmod +x /usr/local/bin/oc-mirror
```

## Start mirror to local Registry

### Figure out the actual OpenShift release

```text
#curl -sH "Accept: application/json"
"https://api.openshift.com/api/upgrades_info/v1/graph?channel=stable-4.22" | jq -r
'.nodes[].version' | sort -V | tail -n 1
```

Client Download See also OCP Mirror Red Hat (For installer, oc, oc mirror,....):
https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable-4.22/

Server / Core OS Images:
https://mirror.openshift.com/pub/openshift-v4/amd64/dependencies/rhcos/4.22/latest/

File for image download:
/var/ocp-airgap-poc/imageset-config.yaml >> File, maybe update the “maxVersion” to the actual
minor Version!!

### Image Mirror with oc-mirror

First time to replicate!
```text
#oc-mirror -c /var/ocp-airgap-poc/imageset-config.yaml --workspace
file:///var/ocp-airgap-poc/workspace --authfile /var/ocp-airgap-poc/auth.json --dest-tls-verify=false
docker://storm4.ocp.polizei.test:5000/openshift/release --v2
```

Second time - after updating the imageset-config.yaml file!

```text
#oc-mirror -c /var/ocp-airgap-poc/imageset-config.yaml --workspace
file:///var/ocp-airgap-poc/workspace --authfile /var/ocp-airgap-poc/auth.json --dest-tls-verify=false
--retry-times 10 --parallel-images 2 --parallel-layers 2
docker://storm4.ocp.polizei.test:5000/openshift/release --v2
```

### Test Commands Registry Tests

Up and running?
```text
#curl -vk https://storm4.ocp.polizei.test:5000
```

Tests!
```text
#curl -k https://storm4.ocp.polizei.test:5000/v2/_catalog | jq .
#curl -k https://storm4.ocp.polizei.test:5000/v2/openshift/release/openshift/release-images/tags/list | jq .
```

Pull Test
```text
#podman pull --tls-verify=false
storm4.ocp.polizei.test:5000/openshift/release/openshift/release-images:4.22.10-x86_64
```

### Check Manifests in the Image Workspace

```text
oc-mirror generated for ImageContentSourcePolicy (ICSP) eg. ImageDigestMirrorSet (IDMS)
Files:
#ls -la /var/ocp-airgap-poc/workspace/working-dir/
```

### Memory Check in /var

```text
#du -sh /var/ocp-airgap-poc/data /var/ocp-airgap-poc/workspace
```

## Pack your registry workspace and take it to the PoC!

Copy Registry the external USB Disk!
```text
#cp -r /var/ocp-airgap-poc/* /external-usb-disk/ocp-airgap-poc
```

Mirror external Bastion Host! Maybe the NAME is gonna change!
```text
##oc-mirror -c /var/ocp-airgap-poc/imageset-config.yaml --workspace
file:///var/ocp-airgap-poc/workspace --authfile /var/ocp-airgap-poc/auth.json --dest-tls-verify=false
--retry-times 10 --parallel-images 2 --parallel-layers 2
docker://storm4.ocp.polizei.test:5000/openshift/release --v2
```

Check the imagedigestmirrorsets - right names?
```text
#oc get imagedigestmirrorsets.config.openshift.io -o yaml
```

ImageDigestMirrorSet to install the New BMH / MachineSets
```text
#oc get imagedigestmirrorset -o json | jq -r '.items[].spec.imageDigestMirrors[].mirrors[]'
storm4.ocp.polizei.test:5000/openshift/release/openshift/release-images
```

storm4.ocp.polizei.test:5000/openshift/release/openshift/release

This will output the list of digests found in the file
```text
#oc image extract --file /release-manifests/0000_50_installer_coreos-bootimages.yaml $(oc
get clusterversion version -o jsonpath='{.status.desired.image}') --confirm
#python3 -c "import re; print(re.findall(r'\"digest-ref\":\s*\"([^\"]+)\"',
open('0000_50_installer_coreos-bootimages.yaml').read()))"
```

Test - is image we need there?
```text
#oc adm release info
storm4.ocp.polizei.test:5000/openshift/release/openshift/release-images:4.22.12-x86_64
--insecure=true
```

Copy whole Directory to USB Harddisk
```text
#rsync -avzP --inplace root@storm4.local:/var/ocp-airgap-poc/
/home/wmarx/po-berlin/harddisk/var/ocp-airgap-poc/
```

# VirtualBMC

## Configure VirtualBMC on storm4

Create a Python virtual environment and install virtualbmc:
```text
#sudo python3 -m venv /opt/vbmc --system-site-packages
#source /opt/vbmc/bin/activate
#pip install virtualbmc
```

Create the vbmc service:
```text
#vim /etc/systemd/system/vbmcd.service
#systemctl daemon-reload
#systemctl start vbmcd
#systemctl status vbmcd
```

Start the virtual BMC daemon
```text
#vbmc
#vbmc list
```

Register existing Nodes!
```text
#vbmc add ocp4-node1 --address 192.168.60.1 --port 6234 --libvirt-uri qemu:///system
--username wmarx --password redhat
#vbmc add ocp4-node2 --address 192.168.60.1 --port 6235 --libvirt-uri qemu:///system
--username wmarx --password redhat
#vbmc add ocp4-node3 --address 192.168.60.1 --port 6236 --libvirt-uri qemu:///system
--username wmarx --password redhat
```

Worker Nodes, second MachineSet - doing that later! (Optional!)

```text
#vbmc add ocp4-node4 --address 192.168.60.1 --port 6237 --libvirt-uri qemu:///system
--username wmarx --password redhat
#vbmc add ocp4-node5 --address 192.168.60.1 --port 6238 --libvirt-uri qemu:///system
--username wmarx --password redhat
```

Start the BMC service for this VM’s
```text
vbmc start ocp4-node1
vbmc start ocp4-node2
vbmc start ocp4-node3
vbmc start ocp4-node4
vbmc start ocp4-node5
```

## Verify the IPMI Interface

Test: Query status of ocp4-node1
```text
#ipmitool -I lanplus -H 192.168.60.1 -U wmarx -P redhat -p 6234 power status
#ipmitool -I lanplus -H 192.168.60.1 -U wmarx -P redhat -p 6234 power on
#ipmitool -I lanplus -H 192.168.60.1 -U wmarx -P redhat -p 6234 power off
```

# Create env & files for the Metal3 Installer

URL: Installing an on-premise cluster with the Agent-based Installer
URL: Deploying OpenShift Container Platform clusters with virtualized control planes
URL: Red Hat Docu / Bonds with agent-config.yaml
URL: API Docu - Provisioning [metal3.io/v1alpha1]

Run Metal3 with VBMC and KVM
Simulate baremetal servers - Create a virtual baremetal environment to “test” baremetal
cloud services such as Cluster API Provider Metal3, Ironic and Bare Metal Operator

## Components of OpenShift Metal3

Cluster-Baremetal-Operator (CBO):
The operator manages and monitors Metal3 services on control plane nodes based on
deployment configs.

BareMetalHost (BMH):
A Custom Resource representing a physical server, storing its online status, MAC addresses,
and BMC credentials. The Server is “stored” in the OCP Database for later use if needed for
additional utilization.

Ironic:
The underlying service (original from OpenStack) handles hardware inspection, PXE booting,
and image deployment.

### 1. First, set your variables (.bashrc)

```text
# Read variables from /var/ocp-airgap-poc (for the tow install Files!)
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub)
REGISTRY_CA=$(cat /var/ocp-airgap-poc/certs/domain.crt)
PULL_SECRET=$(cat /var/ocp-airgap-poc/auth.json | tr -d '\n')
```

### 2. Create install-config.yaml (/var/ocp-airgap-poc)

This mirrors all default domains (quay.io and registry.redhat.io) exclusively to your local
registry (storm4.ocp.polizei.test:5000)

/var/ocp-airgap-poc/installer/install-config.yaml
---------------------------------------------------------------

### 3. Create agent-config.yaml File

/var/ocp-airgap-poc/installer/agent-config.yaml

### 4. Install ISO Image for Deployment

### Cleanup with cleanup-installer.sh

```text
#/var/ocp-airgap-poc/cleanup-installer.sh
```

- Delete Installer Artifacts! (rendezvousIP, auth Directory & .openshift_install*
- Stop all three OpenShift VM’s
- Create/Check the 150 GB vda Harddisks on all three nodes
- Remove Entries from “known_hosts”

### Install Script install-iso-file.sh - create ISO File!

```text
#/var/ocp-airgap-poc/install-iso-file.sh
```

- Sets the variables for: SSH_KEY, PULL_SECRET, REGISTRY_CA)
- Delete Installer Artifacts! (rendezvousIP, auth Directory & .openshift_install*
- Fresh copy of install-config in Installer Directory: /var/ocp-airgap-poc >>
       /var/ocp-airgap-poc/installer

- Fresh copy of agent-config in Installer Directory: /var/ocp-airgap-poc >>
       /var/ocp-airgap-poc/installer
- Create ISO File!

### 5. Install via virt-manager

We have manually created 3 KVM hosts on our KVM Hypervisor in REL9.

# Installing OpenShift

## Start the 3 prepped KVM Hosts on RHEL9

After doing step 4 above (Install Script install-iso-file.sh - create ISO File!)
“#/var/ocp-airgap-poc/install-iso-file.sh”

Now just start the 3 servers to start the installation from the agent.x86_64.iso Boot Image we
created!

## Log & Status during Installation phase

Bootstrap Log
```text
#./openshift-install agent wait-for bootstrap-complete --dir /var/ocp-airgap-poc/installer --log-level
debug
```

```text
#./openshift-install agent wait-for bootstrap-complete --dir=/var/ocp-airgap-poc/installer
--log-level=info
```

OpenShift Log
```text
#tail -f /var/ocp-airgap-poc/installer/.openshift_install.log
```

VIP & API VIP Test Script
/var/ocp-airgap-poc/installer/vip_api_ip_test.sh

Or straight on the nodes:
```text
#journalctl -f -u agent-installer
#journalctl -f -u agent-bootstrapper -u assisted-service
#sudo podman logs service 2>&1 | grep -i "host" | tail -n 20
```

Ignition and Bootservice check
```text
#sudo journalctl -b -n 50 --no-pager
#sudo systemctl list-units --failed
```

# After the Installation - Day2

## DNS-check against the DNS Resolver

```text
#dig @192.168.60.1 api.pb-poc.ocp.polizei.test +short
#dig @192.168.60.1 console-openshift-console.apps.pb-poc.ocp.polizei.test +short
```

## Login Process (Web UI & CLI)

### Cert Trust für *apps Ingress Certificate for Browser

Copy Cert locally on Fedora /home/wmarx/po-berlin
```text
#oc get secret router-ca -n openshift-ingress-operator -o jsonpath='{.data.tls\.crt}' | base64 -d
> router-root-ca.crt
```

1. Zertifikat in den System-Truststore kopieren
```text
#sudo cp ~/router-root-ca.crt /etc/pki/ca-trust/source/anchors/router-root-ca.crt
2. Truststore aktualisieren
#sudo update-ca-trust
#sudo update-ca-trust extract
```

3. Chrome Trust / Privacy and Security > Security > Manage Certs / Import CRT
router-root-ca.crt

### Kubeadmin & Password

User:      kubeadmin
Password:   *See authentication file in the auth Directory*

Export kubeconfig! (On Storm4)
```text
#export KUBECONFIG=/var/ocp-airgap-poc/installer/auth/kubeconfig
```

## Install OpenShift Virtualization Operator via UI

## Install Shared Storage

### NFS Storage

  - Create NDS on Storm4, quick and dirty
```text
             #mkdir -p /var/nfs/ocp-pv1 && sudo chmod 777 /var/nfs/ocp-pv1
             #echo "/var/nfs/ocp-pv1 192.168.60.0/24(rw,sync,no_root_squash)" | sudo tee
             -a /etc/exports
```

  - Create Storage Class Roles ect….
```text
             #oc apply -f /var/ocp-airgap-poc/day2/nfs-provisioner.yaml
```

  - #oc adm policy add-scc-to-user hostmount-anyuid -z nfs-client-provisioner -n
             nfs-provisioner
  - Deploy the Provisioner
```text
             #oc apply -f /var/ocp-airgap-poc/day2/nfs-deployment.yaml
```

  - Patch Storageclass

```text
               #oc patch storageprofiles.cdi.kubevirt.io nfs-dynamic --type=merge -p '{"spec":
               {"claimPropertySets": [{"accessModes":["ReadWriteMany"], "volumeMode":
               "Filesystem"}]}}'
               #Set Default for Cluster in the UI!
```

### NetApp Storage

URL: NetApp Storage in CoE!
User:      admin
Pass:      ********

### NetApp, create a Volume and assign
```text
Name Volume:                  ocp_nfs_pool_poc_pb
Storage VM:                   main
M-IF:                         10.32.97.3
Driver:                       ontap-nas
Junction Path (Mount Path):   /ocp_nfs_pool_poc_pb
Export Policy:                default (0.0.0.0/0)
vs-user:                      vsadmin-pocpb
vs-password:                  *********
```

Folder:
/var/ocp-airgap-poc/day2

### Apply the 3 Trident YAML Manifests

1.
```text
#oc apply -f trident-secret.yaml
```

Explanation:
Securely stores the ONTAP administrator credentials (username vsadmin-pocpb and
password) in the cluster, allowing Astra Trident to authenticate against your NetApp SVM
main.

2.
```text
#oc apply -f trident-backend-config.yaml
```

Explanation:
Configures the logical storage backend connection for Trident. It tells the controller to use the
ontap-nas-economy driver, connect via the management LIF (10.32.97.3), target the SVM
main, and carve out space inside your parent volume ocp_nfs_pool_poc_pb.

3.
```text
#oc apply -f trident-storage-class.yaml
```

Explanation:

Exposes the storage to your cluster users by defining a Kubernetes StorageClass
(netapp-nfs-economy). When users request a PVC using this class, Trident automatically
handles the background mounting and qtree creation.

## Networks in Kubevirt

### VM Network 1 - NNCP & NAD

External Net via VLANID40 + DHCP via DNSMASQ in libvirt on storm4 (192.168.70.0/24) -
DHCP is external!
Netname in KVM: virsh net-edit --network vtn-net
Repeat for all 3 Nodes: Yes
-------------------------------
NNCP:             NNCP - /var/ocp-airgap-poc/day2/nncp-vlan40.yaml
NAD:              NAD  - /var/ocp-airgap-poc/day2/nad-vlan40.yaml

### VM Network 2 - Internal for VM’s, NAD

Repeat for all 3 Nodes: Yes
-------------------------------
Just one NAD for an internal Network (East-West) so that VM’S can talk to each other
NAD Name:
nad-internal-vm

## External Identity Provider htpasswd

URL: OCP Docu - Configuring identity providers

### Requirements

- htpasswd Binary on the Bastion Host
```text
      #sudo dnf install httpd-tools
```

### Create a htpasswd file

/var/ocp-airgap-poc/day2
```text
#htpasswd -c -B -b /tmp/htpasswd wmarx *********
#htpasswd B -b /tmp/htpasswd sabrina redhat12
```

### Create Secret / Credentials in OCP

```text
#oc create secret generic htpasswd-secret --from-file
htpasswd=/var/ocp-airgap-poc/day2/htpasswd -n openshift-config
```

Extract the secret again locally - when you lost it:
```text
#oc extract secret/htpasswd-secret -n openshift-config --to /var/ocp-airgap-poc/day2 --confirm
```

Then update the secret locally (after adding user with “htpassd -b -B….:

```text
#oc set data secret/htpasswd-secret --from-file htpasswd=/tmp/htpasswd -n openshift-config
```

### Configure OAuth Provider

Step1:
Get the oauth Config
```text
#oc get oauth cluster -o yaml > oauth.yaml
```

Step2:
Change the specs in the oauth Config to add a provider

Step3:
Replace the oauth File with the new I-Provider
```text
#oc replace -f oauth.yaml
#watch oc get pods -n openshift-authentication
```

Step4:
Grant Permissions (RBAC)
```text
#oc adm policy add-cluster-role-to-user cluster-admin wmarx
#oc adm policy add-cluster-role-to-user cluster-admin sabrina
```

## Ingress Cert - Replacing with a trusted cert

URL: OCP Docu - Replacing Ingress Certs
Namespace: cert-manager-operator / openshift-ingress

### Requirement

- Install Operator “cert-manager”!

### Step1: Create and issue certs

Create a ClusterIssuer pointing to your internal enterprise Certificate Authority (CA).
File: #oc apply -f /var/ocp-airgap-poc/day2/cluster-issuer.yaml

What does that issue file do for us?
  1. Self-Signed Bootstrapper: We create a temporary, internal-only ClusterIssuer
      (selfsigned-root-issuer).
  2. Automated Root CA Certificate: We ask cert-manager to use that bootstrapper to
      generate a highly secure, dedicated Root CA key pair and save it in a Secret called
      pb-poc-root-ca-secret.
  3. The Production CA Issuer: We create our production-grade ClusterIssuer
      (pb-poc-trust-issuer) pointing to that automated secret.

Check the issuer (it has to be true!):
```text
#oc get issuer pb-poc-trust-issuer -n openshift-ingress
```

### Step2: Create the Wildcard Certificate Request

File:        #oc apply -f /var/ocp-airgap-poc/day2/ingress-wildcard-certificate.yaml
Check:        #oc get certificate apps-wildcard-cert -n openshift-ingress

### Step3: Update Ingress Controller

----------------------------------------------------------------------------
```text
#oc patch ingresscontroller default -n openshift-ingress-operator --type=merge -p
'{"spec":{"defaultCertificate":{"name":"apps-wildcard-tls"}}}'
----------------------------------------------------------------------------
```

Check & Monitor the Process:
```text
#oc rollout status deployment/router-default -n openshift-ingress
```

### Step4: repace new cert for co authentication operator

```text
#oc get secret pb-poc-root-ca-secret -n openshift-ingress -o jsonpath='{.data.tls\.crt}' |
base64 --decode > active-root-ca.crt
#oc create configmap custom-ca --from-file=ca-bundle.crt=active-root-ca.crt -n
openshift-config
#oc patch proxy/cluster --type=merge -p '{"spec":{"trustedCA":{"name":"custom-ca"}}}'
```

### Step5: Trust this Cert in Chrome

Download the cert locally in the day2 directory!
```text
#oc get secret pb-poc-root-ca-secret -n openshift-ingress -o jsonpath='{.data.tls\.crt}' |
base64 --decode > active-root-ca.crt
```

# Additional Worker Nodes (Optional!)

To enable OpenShift to automatically communicate with KVM, spin up new VMs, and register
them as worker nodes, you must configure a virtual out-of-band management layer using a
Redfish emulator.

## The Architecture: How OpenShift talks to KVM

To automate worker provisioning, the platform leverages the native OpenShift Machine API
and the BareMetal Operator (Metal3). The workflow is as follows:

    1. BareMetalHost (BMH) Custom Resource:
        You define the physical or virtual worker machines in OpenShift as BareMetalHost
        resources. This object contains the MAC address of the VM's boot interface and the
        Redfish API URL exposed by sushy-emulator.

    2. MachineSet Scaling:
        When you scale the MachineSet from 0 to 1 (or more), the Machine API controller
        generates a Machine request, claims an available BareMetalHost, and uses
        sushy-emulator to automatically provision RHCOS onto the VM.

## Master nodes from unmanaged to managed

The reason the initial bare metal hosts (Control Plane) are showing as Unmanaged with No
power management in the console is due to a specific safety mechanism applied by the
Assisted Installer during the cluster deployment.

To prevent the cluster's internal Bare Metal Operator (BMO) from interfering with this active
installation process (such as triggering unexpected power cycles, hardware inspections, or
disk-cleaning steps while the nodes are actively writing to disk), it explicitly detaches the
hosts from BMO control

## Apply the BMC Secrets for the BMC Cards

Day2 directory:
/var/ocp-airgap-poc/day2
```text
#oc apply -f bmc-secrets.yaml
```

### Patch the existing BMHs with BMC configuration

The following Resource we have to change:
```text
#oc get provisionings.metal3.io provisioning-configuration -o yaml
#oc apply -f provisioning-configuration.yaml
--------------------------------------------------------------
spec:
 provisioningNetwork: Managed
 provisioningInterface: enp9s0        # Interface on masters connected to provisioning-net
 provisioningIP: 172.22.0.3          # IP address assigned to enp9s0 on the master nodes
 provisioningNetworkCIDR: 172.22.0.0/24     # CIDR of the provisioning network
 provisioningDHCPRange: 172.22.0.10,172.22.0.100 # DHCP range for PXE discovery and booting
 provisioningMacAddresses:
 - "52:54:00:02:2d:fd"            # Node 1 provisioning MAC
 - "52:54:00:fb:3e:4b"            # Node 2 provisioning MAC
 - "52:54:00:62:ba:2c"            # Node 3 provisioning MAC
 preProvisioningOSDownloadURLs: {}
 watchAllNamespaces: true
--------------------------------------------------------------
```

What does it:

    1. provisioningNetwork: Managed: Tells the BareMetal Operator to actively run its own
        DHCP/TFTP servers to network-boot (PXE) your new workers.
    2. provisioningInterface enp9s0: every interface!: Binds the DHCP and TFTP services
        specifically to the isolated provisioning network interface on your master nodes.

   3. provisioningNetworkCIDR: 172.22.0.0/24: Defines the subnet range of our isolated
       network.
   4. provisioningIPRange: 172.22.0.10,172.22.0.100: Tells the internal Ironic service
       which dynamic IP addresses it can hand out to the new hosts while they are PXE
       booting and installing RHCOS.

Verify Operator and DHCP/TFTP Health
```text
#oc get pods -n openshift-machine-api | grep -E "metal3|baremetal|ironic"
```

### Patch the existing BMH Hosts and create node4 & 5

```text
#oc apply -f baremetalhosts.yaml
```

### Create an empty VM Shell for the worker nodes later

Create two virtual machine (e.g., named ocp4-node4/5) on storm4.
- State:
       Keep the VM completely powered off (in shut off state).
- Virtual Disk:
       Attach a blank virtual disk (e.g., /var/lib/libvirt/images/ocp4-node4.qcow2) with a
       capacity matching your existing worker nodes.
- MAC Address:
       Record the MAC address of the primary network interface that is bridged to your
       192.168.60.0/24 subnet (ocp-net)

### The additional BMHosts in OpenShift

Create the Secret:
```text
#oc apply -f /var/ocp-airgap-poc/day2/bmc-secrets.yaml
```

Create and Apply the Standalone BareMetalHost (BMH) Definitions
```text
#oc apply -f /var/ocp-airgap-poc/day2/baremetalhosts.yaml
```

Check Registration Process / Verify Registration!
```text
#oc get bmh -n openshift-machine-api
#vbmc start ocp4-node4
#vbmc start ocp4-node5
#vbmc list
```

If there is a Registration Error still
The BareMetal Operator will issue an IPMI command to restart the VMs. The VMs will boot
directly from the 4th NIC, receive their DHCP lease on 172.22.0.0/24 from Ironic, download
the RHCOS images from your local registry, and proceed with the installation.
```text
#oc annotate bmh ocp4-node4 retry-trigger=$(date +%s) --overwrite -n openshift-machine-api
#oc annotate bmh ocp4-node5 retry-trigger=$(date +%s) --overwrite -n openshift-machine-api
#oc get bmh -n openshift-machine-api
```

### Apply MachineSets & Troubleshooting

/var/ocp-airgap-poc/day2/worker-machineset.yaml

```text
#oc apply -f worker-machineset.yaml
#oc get machines -n openshift-machine-api
#oc get nodes
#oc scale machineset pb-poc-pdvzj-worker -n openshift-machine-api --replicas=2
```

In the case the Provisioning Provision is failing, check the boot order (you need the provision
Network from KVM on Place 1
```text
#oc annotate bmh ocp4-node4 reboot-trigger=$(date +%s) --overwrite -n
openshift-machine-api
#oc annotate bmh ocp4-node5 reboot-trigger=$(date +%s) --overwrite -n
openshift-machine-api
```

```text
# Setzt den Power-State für beide Nodes auf "on" / VM’s are on!
#oc patch bmh ocp4-node4 -n openshift-machine-api --type=merge -p '{"spec":{"online":true}}'
#oc patch bmh ocp4-node5 -n openshift-machine-api --type=merge -p '{"spec":{"online":true}}'
```

```text
# Setzt den Power-State für beide Nodes auf "aus" / VM’s are off!
#oc patch bmh ocp4-node4 -n openshift-machine-api --type merge -p '{"spec":{"online":false}}'
#oc patch bmh ocp4-node5 -n openshift-machine-api --type merge -p '{"spec":{"online":false}}'
```

Monitor the process
```text
# Watch the Metal3 operator write the OS to the disks
oc get bmh -n openshift-machine-api
```

```text
# Track the OpenShift-level machine resource state
oc get machines -n openshift-machine-api
```

```text
# And if we see “pending” CSR’s with
oc get csr >> we have to approve them!
oc get csr -o go-template='{{range .items}}{{if not
.status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs oc adm certificate approve
```

Logs during deployment of additional Nodes to provision!
```text
#oc get pods -n openshift-machine-api | grep metal3
#oc logs -n openshift-machine-api metal3-xxxxxxxxxx -c metal3-ironic -f
```

Resetting whole MAC Addresses ect in MetalB
```text
#oc rollout restart deployment metal3 -n openshift-machine-api
```

Remove Node BMH and machine with force!
```text
#oc patch bmh ocp4-node4 -n openshift-machine-api -p '{"metadata":{"finalizers":[]}}'
--type=merge
```

```text
#oc patch bmh ocp4-node5 -n openshift-machine-api -p '{"metadata":{"finalizers":[]}}'
--type=merge
#oc patch bmh ocp4-node5 -n openshift-machine-api --type json -p '[
   {"op": "remove", "path": "/spec/consumerRef"}
]'
#oc patch machine pb-poc-pdvzj-worker-xxxxx -n openshift-machine-api --type merge -p
'{"metadata":{"finalizers":[]}}'
```
