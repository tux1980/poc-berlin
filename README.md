# Airgapped Environment OpenShift PoC

> **Private repository / dedicated PoC environment**
>
> This README is a Markdown representation of the original PoC document we created to the PoC in Berlin.
> The original wording, explanations, environment values and commands are "partially" intentionally retained.
> The PoC working directory used throughout this README is **`/var/poc-berlin`**. This is a private Repository.

---

## Table of Contents

1. [Overview](#overview)
2. [Network stuff in KVM](#network-stuff-in-kvm)
3. [VirtualBMC with OpenShift BMO](#virtualbmc-with-openshift-bmo)
4. [Overview Install Process of OpenShift](#overview-install-process-of-openshift)
5. [Local Registry for Airgapped Installation](#local-registry-for-airgapped-installation)
6. [Use OC-Mirror!](#use-oc-mirror)
7. [Installing OpenShift](#installing-openshift)
8. [After Installation - Day Two operations](#after-installation---day-two-operations)
9. [Login Process (Web UI & CLI)](#login-process-web-ui--cli)
10. [Install OpenShift Virtualization Operator via UI](#install-openshift-virtualization-operator-via-ui)
11. [Install Shared Storage](#install-shared-storage)
12. [Change internal OCP Registry (Ephemeral to Persistence)](#change-internal-ocp-registry-ephemeral-to-persistence)
13. [Networks in Kubevirt](#networks-in-kubevirt)
14. [External Identity Provider htpasswd](#external-identity-provider-htpasswd)
15. [Create two RHEL VM's in Namespace via the OCP Virt UI!](#create-two-rhel-vms-in-namespace-via-the-ocp-virt-ui)
16. [Create "not-rhel" templates!](#create-not-rhel-templates)
17. [Create Windows Machines!](#create-windows-machines)
18. [Additional Worker Nodes (Optional!)](#additional-worker-nodes-optional)
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

RHEL 9.x Access on our Bastion Host (Standard Installation! Don't use minimal Installation)  
```text
#storm4 (Alias for ssh access to my Remote Bastion Host)

On Bastion Host you need couple of OpenShift clients:

** oc
** oc-mirror  
** virtctl  
** openshift-install  
** skopeo  
** podman  
** jq / yq  
** git  
** tmux  
** vim  
** curl  

And execute:  
#oc completion bash > /dev/null && oc completion bash | sudo tee /etc/profile.d/bash_completion_oc.sh > /dev/null

```

Directory: Image Location on Storm4 for libvirt Images!
/var/lib/libvirt/images

Directory: Location for everything which we need for the PoC!
/var/poc-berlin

# Network stuff in KVM
Since, we're supposed to work really "offline" - disable the Internet Access on storm4 for the CoreOS Nodes:
```text
Disable Internet Access except for the NetApp (10.32.97.3)
#iptables -I FORWARD 1 -o enp132s0f0 -s 192.168.60.0/24 -d 10.32.97.3 -j ACCEPT
#iptables -A FORWARD -o enp132s0f0 -s 192.168.60.0/24 -j DROP

Access auf NetApp testen:
#oc debug node/ocp4-node1.pb-poc.ocp.polizei.test -- chroot /host nc -zvw3 10.32.97.3 443

Delete Rules - Activate again (if really necessary for some test stuff!)
#iptables -D FORWARD -o enp132s0f0 -s 192.168.60.0/24 -d 10.32.97.3 -j ACCEPT 
#iptables -D FORWARD -o enp132s0f0 -s 192.168.60.0/24 -j DROP
```

## Create the 3 libvirt nets

### OpenShift Machine Network

```text
#virsh net-define /var/poc-berlin/ocp-net.xml
#virsh net-start ocp-net
#virsh net-autostart ocp-net
```

### VM-Network

```text
#virsh net-define /var/poc-berlin/vm-net.xml
#virsh net-start vtn-net
#virsh net-autostart vtn-net
```

### Provisioning-Network (Day2 Directory!)

```text
#virsh net-define /var/poc-berlin/day2/provisioning-net.xml
#virsh net-start vtn-net
#virsh net-autostart vtn-net
```
### Now, we should have 3 libvirt nets

Net1: ocp-net                    (install / machine network for LACP Install!)  
Net2: vtn-net                    (install / for virtual machines)  
Net3: provisioning-net           (BMH / Metal3, OpenShift)  

Optional: Delete a network! (Detach the Interfaces afterwards manually…
```text
#virsh net-destroy ocp-net 2>/dev/null
#virsh net-undefine ocp-net 2>/dev/null
```

Optional: And new again……
```text
#virsh net-define /var/poc-berlin/ocp-net.xml
#virsh net-start ocp-net
#virsh net-autostart ocp-net
```

## Create the 3 VM's with KVM/QEMU for my OpenShift Compact Cluster
ocp4-node1:  
```text
Storage Size Disk Device:
150GB

Memory / RAM:
32GB

CPU Assignmet:
8vCPU

SATA CDROM - Boot ISO OpenShift:
/PATH/agent.x86_64.iso (The Install ISO we creating later...)

Network Interfaces:
ocp-net / Leg1:         52:54:00:aa:bb:01
ocp-net / Leg2:         52:54:00:aa:bb:21
VM-Network:             52:54:00:5c:b6:a3
Prov. Network Ironic:   52:54:00:02:2d:fd

Boot Sequence:
1. VirtIO Disk
2. CDROM
3. NIC: First Leg "ocp-net" / 52:54:00:aa:bb:01
```
ocp4-node2:  
```text
Storage Size Disk Device:
150GB

Memory / RAM:
32GB

CPU Assignmet:
8vCPU

SATA CDROM - Boot ISO OpenShift:
/PATH/agent.x86_64.iso (The Install ISO we creating later...)

Network Interfaces:
ocp-net / Leg1:         52:54:00:aa:bb:02
ocp-net / Leg2:         52:54:00:aa:bb:22
VM-Network:             52:54:00:ab:fe:cb
Prov. Network Ironic:   52:54:00:fb:3e:4b

Boot Sequence:
1. VirtIO Disk
2. CDROM
3. NIC: First Leg "ocp-net" / 52:54:00:aa:bb:02
```

ocp4-node3:  
```text
Storage Size Disk Device:
150GB

Memory / RAM:
32GB

CPU Assignmet:
8vCPU

SATA CDROM - Boot ISO OpenShift:
/PATH/agent.x86_64.iso (The Install ISO we creating later...)

Network Interfaces:
ocp-net / Leg1:         52:54:00:aa:bb:03
ocp-net / Leg2:         52:54:00:aa:bb:23
VM-Network:             52:54:00:64:e5:9d
Prov. Network Ironic:   52:54:00:62:ba:2c

Boot Sequence:
1. VirtIO Disk
2. CDROM
3. NIC: First Leg "ocp-net" / 52:54:00:aa:bb:03
```

## Attach Interfaces for all 3 libvirt networks!

Hybrid Nodes (Compact Cluster Nodes, Control Plane & Worker)
The MAC addresses we got from the VM Configuration!
```text
OCP Net - Leg-1:
#virsh attach-interface --domain ocp4-node1 --type network --source ocp-net --model virtio --mac 52:54:00:aa:bb:01 --config --live
#virsh attach-interface --domain ocp4-node2 --type network --source ocp-net --model virtio --mac 52:54:00:aa:bb:02 --config --live
#virsh attach-interface --domain ocp4-node3 --type network --source ocp-net --model virtio --mac 52:54:00:aa:bb:03 --config --live
```
```text
OCP Net - Leg-2:
#virsh attach-interface --domain ocp4-node1 --type network --source ocp-net --model virtio --mac 52:54:00:aa:bb:21 --config --live
#virsh attach-interface --domain ocp4-node2 --type network --source ocp-net --model virtio --mac 52:54:00:aa:bb:22 --config --live
#virsh attach-interface --domain ocp4-node3 --type network --source ocp-net --model virtio --mac 52:54:00:aa:bb:23 --config --live
```
```text
VTN-Net:
#virsh attach-interface --domain ocp4-node1 --type network --source vtn-net --model virtio --mac 52:54:00:5c:b6:a3 --config --live
#virsh attach-interface --domain ocp4-node2 --type network --source vtn-net --model virtio --mac 52:54:00:ab:fe:cb --config --live
#virsh attach-interface --domain ocp4-node3 --type network --source vtn-net --model virtio --mac 52:54:00:64:e5:9d --config --live
```
```text
Provisioning Network:
#virsh attach-interface --domain ocp4-node1 --type network --source provisioning-net --model virtio --mac 52:54:00:02:2d:fd --config --live
#virsh attach-interface --domain ocp4-node2 --type network --source provisioning-net --model virtio --mac 52:54:00:fb:3e:4b --config --live
#virsh attach-interface --domain ocp4-node3 --type network --source provisioning-net --model virtio --mac 52:54:00:62:ba:2c --config --live
```

Optional: Two additional Worker Nodes
```text
OCP Net - Leg-1:
#virsh attach-interface --domain ocp4-node4 --type network --source ocp-net --model virtio --mac 52:54:00:01:c6:89 --config --live
#virsh attach-interface --domain ocp4-node5 --type network --source ocp-net --model virtio --mac 52:54:00:dd:ed:70 --config --live
```
```text
OCP Net - Leg-2:
#virsh attach-interface --domain ocp4-node4 --type network --source ocp-net --model virtio --mac 52:54:00:aa:bb:24 --config --live
#virsh attach-interface --domain ocp4-node5 --type network --source ocp-net --model virtio --mac 52:54:00:aa:bb:25 --config --live
```
```text
VTN-Net:
#virsh attach-interface --domain ocp4-node4 --type network --source vtn-net --model virtio --mac 52:54:00:db:03:17 --config --live
#virsh attach-interface --domain ocp4-node5 --type network --source vtn-net --model virtio --mac 52:54:00:d4:b4:1c --config --live
```
```text
# Provisioning Network:
#virsh attach-interface --domain ocp4-node4 --type network --source provisioning-net --model virtio --mac 52:54:00:b2:03:ce --config
#virsh attach-interface --domain ocp4-node5 --type network --source provisioning-net --model virtio --mac 52:54:00:c9:c6:76 --config
```

### Optional: Example - In the case - we have to detach these interfaces again...
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
  virsh domiflist $node | awk -v n="$node" '/ocp-net|provisioning-net|vtn-net/ {printf "%-12s | %-18s | %s\n", n, $3, $5}'
done; echo "------------"
```

### Optional: Remove the Interfaces (example):
```text
#virsh detach-interface --domain ocp4-node1 --type network --mac 52:54:00:xx:xx:xx --config --live
#virsh detach-interface --domain ocp4-node2 --type network --mac 52:54:00:xx:xx:xx --config --live
#virsh detach-interface --domain ocp4-node3 --type network --mac 52:54:00:xx:xx:xx --config --live
```

### Network Node Config (virsh)

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
#for node in ocp4-node1 ocp4-node2 ocp4-node3 ocp4-node4 ocp4-node5; do
  echo "=== Schnittstellen für $node ==="
  virsh domiflist "$node" | grep -E "ocp-net|provisioning-net|vtn-net"
  echo ""
done
```

Fast Check for all MAC Addresses on the VM’s
```text
#for node in ocp4-node1 ocp4-node2 ocp4-node3 ocp4-node4 ocp4-node5; do
  echo "------------"
  virsh domiflist "$node" | awk -v n="$node" '/ocp-net|provisioning-net|vtn-net/ {
    printf "%-12s | %-18s | %s\n", n, $3, $5
  }'
done
echo "------------"
```

Status Check all Networks in KVM
```text
#virsh net-list --all
```

## Expected Outcome:
```text
ocp-net               active yes        yes  
provisioning-net      active yes        yes  
vtn-net               active yes        yes
```
If we have trouble creating the "provisioning-net" net as internal switch the "virbr-prov" IF didn't get created:
```text
#nmcli connection add type bridge con-name virbr-prov ifname virbr-prov autoconnect yes
#nmcli connection up virbr-prov
```

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
bridge interfaces by default we update the virtual network XML file (ocp-net.xml and
vm-net.xml) to explicitly bind dnsmasq to our new VLAN sub-interfaces (virbr1.40 for the
machine network and virbr2.100 for the VM Network). This ensures that when virtual
machines boot up and request IP addresses over tagged VLAN traffic, dnsmasq captures
those requests and hands out the proper DHCP leases.

### VLAN40 - ocp-net (virbr1.40)

```text
# Create the VLAN 40 profile with link-local IP
nmcli connection add type vlan con-name virbr1.40 ifname virbr1.40 dev virbr1 id 40 ipv4.method manual ipv4.addresses 192.168.60.1/32 connection.zone trusted
```

```text
# Add the persistent host routes (including .14 and .15)
nmcli connection modify virbr1.40 +ipv4.routes "192.168.60.11/32, 192.168.60.12/32, 192.168.60.13/32, 192.168.60.14/32, 192.168.60.15/32, 192.168.60.10/32, 192.168.60.20/32"
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
# VirtualBMC with OpenShift BMO

Run Metal3 with VBMC and KVM  
Simulate baremetal servers - Create a virtual baremetal environment to “test” baremetal  
cloud services such as Cluster API Provider Metal3, Ironic and Bare Metal Operator  

### Components of OpenShift Metal3

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


### Configure VirtualBMC on storm4

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

### Verify the IPMI Interface

Test: Query status of ocp4-node1
```text
#ipmitool -I lanplus -H 192.168.60.1 -U wmarx -P redhat -p 6234 power status
#ipmitool -I lanplus -H 192.168.60.1 -U wmarx -P redhat -p 6234 power on
#ipmitool -I lanplus -H 192.168.60.1 -U wmarx -P redhat -p 6234 power off
```

# Overview Install Process of OpenShift

## Architectural Summary
```text
Nodes:                       3 Compact Nodes (Master + Worker role combined)
Ingress Virtual IPs (VIPs):  192.168.60.20
API VIP:                     192.168.60.10
Node IPs:
 - ocp4-node1.poc.ocp.berlin.test: 192.168.60.11 (Rendezvous Host!!)  
 - ocp4-node2.poc.ocp.berlin.test: 192.168.60.12  
 - ocp4-node3.poc.ocp.berlin.test: 192.168.60.13
```

## Design / Architecture

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
#mkdir -p /var/poc-berlin/{certs,data,metadata,workspace}
#cd /var/poc-berlin
```

### TLS-Certs for local Registry

```text
#openssl req -newkey rsa:4096 -nodes -sha256 \
  -keyout /var/poc-berlin/certs/domain.key \
  -x509 -days 365 \
  -out /var/poc-berlin/certs/domain.crt \
  -subj "/CN=storm4.ocp.berlin.test" \
  -addext "subjectAltName=DNS:storm4.ocp.berlin.test,IP:192.168.60.1"
```

## Podman Registry

### Start Podman Cocker Registry

Image we need:
```text
#podman inspect docker.io/library/registry:2 --format '{{.RepoTags}} {{.Digest}}'
```

Test it:
```text
#podman run --rm \
  --entrypoint echo \
  -p 5000:5000 \
  -v /var/poc-berlin/data:/var/lib/registry:z \
  -v /var/poc-berlin/certs:/certs:z \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  docker.io/library/registry:2 \
  "Syntax and flags are valid!"
```

Run it!
```text
#podman run -d \
  --name local-registry \
  --restart=always \
  -p 5000:5000 \
  -v /var/poc-berlin/data:/var/lib/registry:z \
  -v /var/poc-berlin/certs:/certs:z \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  docker.io/library/registry:2
```

Copy whole Directory to USB Harddisk
```text
#rsync -avzP --inplace --exclude='*pinned_*.yaml' root@storm4.local:/var/poc-berlin/ /home/wmarx/po-berlin/harddisk/var/poc-berlin/
```

### Take the docker.io/library/registry:2 with you!

Download the Registry Image & save it
```text
#podman pull docker.io/library/registry:2
#podman tag docker.io/library/registry:2 local-poc-registry:2
#podman save -o /var/poc-berlin/harddisk-test/registry-image.tar local-poc-registry:2
```

Load the Image in the air-gapped env!
```text
#podman load -i /var/poc-berlin/harddisk-test/registry-image.tar
```
You might inspect the registry now, is now “local” - ignore the docker.io address….
```text
#podman inspect local-poc-registry:2
```

Start Container Image/Registry airgapped!
```text
#podman run -d \
  --name local-registry \
  --restart=always \
  -p 5000:5000 \
  -v /var/poc-berlin/data:/var/lib/registry:z \
  -v /var/poc-berlin/certs:/certs:z \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  local-poc-registry:2
```

### Test Commands Registry Tests

#### Up and running?
```text
#oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
```

#### Disable Default Catalog sources to make sure nothing runs via the deafaults!
```text
#curl -vk https://storm4.ocp.berlin.test:5000

#### Further Tests!
```text
#curl -k https://storm4.ocp.berlin.test:5000/v2/_catalog | jq .
#curl -k https://storm4.ocp.berlin.test:5000/v2/openshift/release/openshift/release-images/tags/list | jq .
```

#### Pull Test
```text
#podman pull --tls-verify=false storm4.ocp.berlin.test:5000/openshift/release/openshift/release-images:4.22.10-x86_64
```

#### Memory Check in /var

```text
#du -sh /var/poc-berlin/data /var/poc-berlin/workspace
```

# Use OC-Mirror!

```text
#curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/oc-mirror.tar.gz && tar -xzf oc-mirror.tar.gz -C /usr/local/bin/ && chmod +x /usr/local/bin/oc-mirror
```

## Start mirror to local Registry

### Figure out the actual OpenShift release

```text
#curl -sH "Accept: application/json" "https://api.openshift.com/api/upgrades_info/v1/graph?channel=stable-4.22" | jq -r '.nodes[].version' | sort -V | tail -n 1
```

Client Download See also OCP Mirror Red Hat (For installer, oc, oc mirror,....):  
https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable-4.22/

Server / Core OS Images:  
https://mirror.openshift.com/pub/openshift-v4/amd64/dependencies/rhcos/4.22/latest/

File for image download:  
/var/poc-berlin/imageset-oc-mirror-config.yaml >> File, maybe update the “maxVersion” to the actual
minor Version!!

### Figure out if an operator is really there
Example:  
```text
#oc-mirror --v2 list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.22 | grep -E 'cluster-logging|advanced-cluster-management|multicluster-engine|node-healthcheck|fence-agents|self-node'
```

### Image Mirror with oc-mirror

First time to replicate!
```text
#oc-mirror \
  -c /var/poc-berlin/imageset-oc-mirror-config.yaml \
  --workspace file:///var/poc-berlin/workspace \
  --authfile /var/poc-berlin/auth.json \
  --dest-tls-verify=false \
  docker://storm4.ocp.berlin.test:5000/openshift/release \
  --v2
```

### Check Manifests in the Image Workspace

```text
oc-mirror generated for ImageContentSourcePolicy (ICSP) eg. ImageDigestMirrorSet (IDMS - oc-mirror V2)
Files:
#ls -la /var/poc-berlin/workspace/working-dir/cluster-resources
```
Second time - after updating the imageset-oc-mirror-config.yaml file!  
```text
#oc-mirror \
  -c /var/poc-berlin/imageset-oc-mirror-config.yaml \
  --workspace file:///var/poc-berlin/workspace \
  --authfile /var/poc-berlin/auth.json \
  --dest-tls-verify=false \
  --retry-times 10 \
  --parallel-images 1 \
  --parallel-layers 1 \
  docker://storm4.ocp.berlin.test:5000/openshift/release \
  --v2
```

### Alternative - mirror a single Image with "oc image mirror"!   
Find out the latest 3 tags of an image you want to pull in the offline registry:  
```text
skopeo list-tags docker://registry.redhat.io/cert-manager/cert-manager-operator-rhel9 --authfile /var/poc-berlin/auth.json | jq -r '.Tags[]' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | tail -n 3
```
Than you can download a single Image with "oc image" - means with the original OpenShift Command Line Tool
```text
#oc image mirror registry.redhat.io/cert-manager/cert-manager-operator-rhel9:v1.20.1 storm4.ocp.polizei.test:5000/openshift/release/cert-manager/cert-manager-operator-rhel9:v1.20.1 --insecure=true
```
### Sync new Sources
Sync the new Sources & catalogs AFTER doing oc-mirror - all manifest are getting created automatically in:  
/var/poc-berlin/workspace/working-dir/cluster-resources/  
```text
Either do single files (Like the cs-files and idms file). cc=Community Catalog  //  cs=Certified Store
#oc apply -f /var/poc-berlin/workspace/working-dir/cluster-resources/cs-redhat-operator-index-v4-22.yaml
#oc apply -f /var/poc-berlin/workspace/workspace/working-dir/cluster-resources/idms-oc-mirror.yaml

Or just do the whole directory:
#oc apply -f /var/poc-berlin/workspace/working-dir/cluster-resources/
```

```text
#rsync -avzP --inplace --exclude='*pinned_*.yaml' root@storm4.local:/var/poc-berlin/ /home/wmarx/po-berlin/harddisk/var/poc-berlin/
```

Optional Copy the Delta-Data to USB Harddisk
```text
#rsync -avzP --inplace --exclude='*pinned_*.yaml' root@storm4.local:/var/poc-berlin/ /home/wmarx/po-berlin/harddisk/var/poc-berlin/
```

## Pack your registry workspace and take it to the PoC!

Copy Registry the external USB Disk!
```text
#cp -r /var/poc-berlin/* /external-usb-disk/ocp-airgap-poc
```

Mirror external Bastion Host! Maybe the NAME is gonna change!
```text
##oc-mirror \
  -c /var/poc-berlin/imageset-oc-mirror-config.yaml \
  --workspace file:///var/poc-berlin/workspace \
  --authfile /var/poc-berlin/auth.json \
  --dest-tls-verify=false \
  --retry-times 10 \
  --parallel-images 2 \
  --parallel-layers 2 \
  docker://storm4.ocp.berlin.test:5000/openshift/release \
  --v2
```
# Installing OpenShift

#### 0. URL's 

- [OpenShift Documentation - Installation & Update](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/architecture/architecture-installation)
- [Installing an on-premise cluster with the Agent-based Installer](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_an_on-premise_cluster_with_the_agent-based_installer/preparing-to-install-with-agent-based-installer#agent-based-installer-recommended-resources_preparing-to-install-with-agent-based-installer)
- [Deploying OpenShift Container Platform clusters with virtualized control planes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html-single/virtualized_control_planes/index#vcp-overview)
- [Red Hat Docu / Bonds with agent-config.yaml](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_an_on-premise_cluster_with_the_agent-based_installer/preparing-to-install-with-agent-based-installer)
- [API Docu - Provisioning [metal3.io/v1alpha1]](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/provisioning_apis/provisioning-metal3-io-v1alpha1)
- [Under the hood of OpenShift update mechanism](https://rubenrodrigues.fr/under-the-hood-of-ocp-upgrade-mechanism/)
- [Latest technical articles & videos, Like Let's Encrypt u.a.](https://www.certdepot.net/))

## First, create auth.json & set your variables (.bashrc)

Create Authfile (We need pull-secret,RH registry, Podman Registry):  
```text
Create the empty File:
#echo '{}' > /var/poc-berlin/auth.json // Create auth file with an empty json object!
```

#### 1. Mein Pull Secret in Auth File einfügen:
```text
printf '%s\n' '[PULL_SECRET from console.redhat.com]' > /var/poc-berlin/auth.json
```
#### 2. Red Hat Registry Login
```text
#podman login registry.redhat.io --authfile /var/poc-berlin/auth.json
```

#### 3. Quay.io Release Login (wird für das Release-Image benötigt)
```text
#podman login quay.io --authfile /var/poc-berlin/auth.json
```

#### 4. Login PoC Offline Registry: Give auth file to local Registry
```text
#podman login storm4.ocp.berlin.test:5000 --tls-verify=false --authfile /var/poc-berlin/auth.json
```
#### 5. Fixing the environment variables 

```text
# Read variables from /var/poc-berlin (for the two install Files!)
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub)
REGISTRY_CA=$(cat /var/poc-berlin/certs/domain.crt)
PULL_SECRET=$(cat /var/poc-berlin/auth.json | tr -d '\n')

Or fix via entries in our local .bashrc:
export SSH_KEY=$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub)
export REGISTRY_CA=$(cat /var/poc-polizei/certs/domain.crt)                     
export PULL_SECRET=$(cat /var/poc-polizei/auth.json | tr -d '\n')
export KUBECONFIG=/var/poc-berlin/installer/auth/kubeconfig

```

## Install Config & Agent Config

#### 1. Create install-config.yaml (/var/poc-berlin)

This mirrors all default domains (quay.io and registry.redhat.io) exclusively to your local
registry (storm4.ocp.berlin.test:5000)
```text
Remark:
Actually the install-config is accommodated in the /var/poc-berlin/ directory - we just copy them to the "installer" Directory since those files just temporay in this directory (the installer directory)
/var/poc-berlin/installer/install-config.yaml
```
#### 1.2 RootDevice Hints!
If the default entry does not works - you have to figure this on the CoreOS Console.  
Just boot the CoreOS OCP Node with the agent.iso file and figure out the Hints:  
```text
#lsblk -o NAME,SIZE,MODEL,SERIAL,WWN,TYPE
#udevadm info --query=property --name=/dev/DISK | grep -E "ID_WWN|ID_SERIAL|ID_BUS"

You get something like:
ID_BUS=ata
ID_SERIAL=WDC_WD30NMZW-11GX6S1_WD-WX11D98RE7AJ
ID_SERIAL_SHORT=WD-WX11D98RE7AJ
ID_WWN=0x50014ee6b3e2451b
ID_WWN_WITH_EXTENSION=0x50014ee6b3e2451b

Then take the WWN Number in the install-config.yaml File:
Example:
rootDeviceHints:
          wwn: "0x50014ee6b3e2451b"
```
---------------------------------------------------------------

#### 2. Create agent-config.yaml (/var/poc-berlin)
```text
Remark:
Actually the agent-config is accommodated in the /var/poc-berlin/ directory - we just copy them to the "installer" Directory since those files just temporay in this directory (the installer directory)
/var/poc-berlin/installer/agent-config.yaml
```
#### 3. Install ISO Image for Deployment

Cleanup with cleanup-installer.sh

```text
#/var/poc-berlin/cleanup-installer.sh
```

- Delete Installer Artifacts! (rendezvousIP, auth Directory & .openshift_install*
- Stop all three OpenShift VM’s
- Create/Check the 150 GB vda Harddisks on all three nodes
- Remove Entries from “known_hosts”

Install-iso-file.sh - create ISO File!

```text
#/var/poc-berlin/install-iso-file.sh
```

- Sets the variables for: SSH_KEY, PULL_SECRET, REGISTRY_CA)
- Delete Installer Artifacts! (rendezvousIP, auth Directory & .openshift_install*
- Fresh copy of install-config in Installer Directory: /var/poc-berlin >>
       /var/poc-berlin/installer

- Fresh copy of agent-config in Installer Directory: /var/poc-berlin >>
       /var/poc-berlin/installer
- Create ISO File!

### Start the 3 prepped KVM Hosts on RHEL9

After doing step 4 above (Install Script - create ISO File!)  

Now just start the 3 servers to start the installation from the agent.x86_64.iso Boot Image we
created!  

### Log & Status during Installation phase

Bootstrap Log
```text
#./openshift-install agent wait-for bootstrap-complete --dir /var/poc-berlin/installer --log-level debug
```

```text
#./openshift-install agent wait-for bootstrap-complete --dir=/var/poc-berlin/installer --log-level=info
```

OpenShift Log
```text
#tail -f /var/poc-berlin/installer/.openshift_install.log
```
### VIP & API VIP Test Script
This script monitors the availability of the OCP API, the Ignition Port & the Ingress VIP
```text
/var/poc-berlin/installer/vip_api_ip_test.sh
=== OPENSHIFT VIP & BOOTSTRAP MONITORING ===
API VIP (192.168.60.10):       ONLINE
Ignition Server (Port 22623):  ONLINE
Ingress VIP (192.168.60.20):   ONLINE
--------------------------------------------
```
Or straight on the nodes:
```text
#journalctl -f -u agent-installer
#journalctl -f -u agent-bootstrapper -u assisted-service
#podman logs service 2>&1 | grep -i "host" | tail -n 20
```

Ignition and Bootservice check
```text
#journalctl -b -n 50 --no-pager
#systemctl list-units --failed
```

# After Installation - Day Two operations
### Check the imagedigestmirrorsets - right names?
```text
Get all Mirrors / Image Sets:
oc get imagedigestmirrorset -o json | jq -r '.items[].spec.imageDigestMirrors[].mirrors[]'

Get the config as yaml file:
#oc get imagedigestmirrorsets.config.openshift.io -o yaml
```

### This will output the list of digests found in the file (Optional!)
This section extracts the internal CoreOS boot image manifest (0000_50_installer_coreos-bootimages.yaml) directly from the cluster's active release payload using "oc image extract".   
A inline Python script then scans the manifest to extract and list all required image SHA digests. This step verifies that the exact RHCOS boot images needed by Metal3 and Ironic for node provisioning are present and correctly referenced in your air-gapped registry.

```text
#oc image extract \
  --file /release-manifests/0000_50_installer_coreos-bootimages.yaml \
  "$(oc get clusterversion version -o jsonpath='{.status.desired.image}')" \
  --confirm
#python3 -c "import re; print(re.findall(r'\"digest-ref\":\s*\"([^\"]+)\"', open('0000_50_installer_coreos-bootimages.yaml').read()))"
```

### Test - is image we need there?
```text
#oc adm release info storm4.ocp.berlin.test:5000/openshift/release/openshift/release-images:4.22.12-x86_64 --insecure=true
```

### DNS-check against the DNS Resolver

```text
#dig @192.168.60.1 api.poc.ocp.berlin.test +short
#dig @192.168.60.1 console-openshift-console.apps.poc.ocp.berlin.test +short
```

# Login Process (Web UI & CLI)
### Login via "oc" or Web UI  


```text

Command Line:
#oc login -u kubeadmin -p xxxx-xxxxxx-xxxxx-xxxxxx https://api.poc.ocp.berlin.test:6443"
WebUI:
https://console-openshift-console.apps.poc.ocp.berlin.test

Or:
Export the kubeconfig after Installation:
#export KUBECONFIG=/var/poc-berlin/installer/auth/kubeconfig

In case you delete the "auth" directory with the KubeConfig:
Create a new one - if you have still some cluster-admin credentials...
#oc config new-admin-kubeconfig > auth/kubeconfig
```
### Create a Context
```text
An OpenShift context is a set of access parameters stored inside your ~/.kube/config file. It binds three elements together:
* a Cluster (API endpoint)
* a User (authentication credentials)
* a Namespace/Project (scope)

# Get Context
oc config get-contexts

# Create Context
oc login -u kubeadmin -p xxxx-xxxxxx-xxxxx-xxxxxx https://api.poc.ocp.berlin.test:6443 --context=admin-poc

# Switch Context:
oc config use-context admin-poc
```

## Cert Trust für *apps Ingress Certificate for Browser

Copy Cert locally on Fedora /home/wmarx/po-berlin
```text
#oc get secret router-ca -n openshift-ingress-operator -o jsonpath='{.data.tls\.crt}' | base64 -d > router-root-ca.crt
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

## Kubeadmin & Password

User:      kubeadmin
Password:   *See authentication file in the auth Directory*

Export kubeconfig! (On Storm4)
```text
#export KUBECONFIG=/var/poc-berlin/installer/auth/kubeconfig
```

# Install OpenShift Virtualization Operator via UI
### Install Kubevirt Operator via WebUI

#### Patching the Hyperconverged for offline configuration   
[URL: Disable automatic updates for all system-defined boot sources](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/storage#virt-managing-auto-update-all-system-boot-sources_virt-automatic-bootsource-updates)  
Disable download of VM images from RH:  
** Fedora  
** RHEL  
** CentOS  
```text
#oc patch hyperconvergeds.v1beta1.hco.kubevirt.io kubevirt-hyperconverged -n openshift-cnv --type json -p '[{"op": "replace", "path": "/spec/enableCommonBootImageImport","value": false}]'
```

### Install nmstate/multus Operator via WebUI
### Install MTV Operator via WebUI

# Install Shared Storage

### NetApp Storage
[URL: Trident 26.06 documentation](https://docs.netapp.com/us-en/trident/index.html)  
[URL: Releases in Github / Version History](https://github.com/NetApp/trident/releases)  
[URL: Dependencies Container images and corresponding Kubernetes versions](https://docs.netapp.com/us-en/trident/trident-get-started/requirements.html#container-images-and-corresponding-kubernetes-versions)  
[URL: Install Trident using OpenShift OperatorHub](https://docs.netapp.com/us-en/trident/trident-install/openshift-operator-deploy.html)  
  

First, Install the NetApp Trident Operator / CR TridentOrchestrators via the WebUI  
  
Since we working offline, we "might" have to do something about it and establish it more or less manually:  
In this case:  

#### Check Out the Trident Operator 
```text
#podman inspect storm4.ocp.polizei.test:5000/openshift/release/netapp/trident-operator:26.06.1
#curl -s "https://quay.io/api/v1/repository/netapp/trident-operator/tag/" | jq -r '.tags[].name' | sort -V

If not there:
#podman pull quay.io/netapp/trident-operator:26.06.1
#podman tag quay.io/netapp/trident-operator:26.06.1 storm4.ocp.polizei.test:5000/openshift/release/netapp/trident-operator:26.06.1
#podman push --tls-verify=false storm4.ocp.polizei.test:5000/openshift/release/netapp/trident-operator:26.06.1
```

#### Check Out the Trident Orchestrator CR  
```text
#podman inspect storm4.ocp.polizei.test:5000/openshift/release/netapp/trident:26.06.1
#curl -s "https://quay.io/api/v1/repository/netapp/trident/tag/" | jq -r '.tags[].name' | sort -V

If not there:
#podman pull quay.io/netapp/trident:26.06.1  
#podman tag quay.io/netapp/trident:26.06.1 storm4.ocp.polizei.test:5000/openshift/release/netapp/trident:26.06.1
#podman push --tls-verify=false storm4.ocp.polizei.test:5000/openshift/release/netapp/trident:26.06.1
```
#### Install Trident Operator manuelly
Sidecars:  
All in one file here:   
```text
/var/poc-berlin/day2/trident-get-csi-sidecars.sh (There you can observe all the images we need)
* trident-autosupport:26.06
* sig-storage/csi-node-driver-registrar:v2.17.0
* sig-storage/csi-provisioner:v6.3.0
* sig-storage/csi-attacher:v4.11.0
* sig-storage/csi-resizer:v2.1.0
* sig-storage/csi-snapshotter:v8.6.0
```
#### Install Operator and Trident-Orchestrator
Be aware:  
We are creating everything here in one yaml file:  
```text
/var/poc-berlin/day2/trident-create-operator-and-orchestretor.yaml
```
#### Additional Commands
Check Backend! 
```text
#oc get tbc -n trident
```
```text
Check Storageclass:
#oc get tridentstorageclass -n trident
```
Check Trident Resource Trident-Orchestrator:
```text
#oc get torc -n trident
```

Storgeclass is broken and cannot be deleted?  
```text
#oc patch tridentstorageclass netapp-nfs-economy -n trident --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
``` 

Since we blockes everything via an IPTABLES Rule - after a reboot - apply this again to make sure the cluster is offline but  
we still can access the NetApp Storage:
```text
#iptables -I FORWARD 1 -o enp132s0f0 -s 192.168.60.0/24 -d 10.32.97.3 -j ACCEPT
#iptables -A FORWARD -o enp132s0f0 -s 192.168.60.0/24 -j DROP
```

#### Update Trident Operator AND Trident Orchestrator manually
Step1:  
You just have to pull, tag & pull again, as it is described above, only change the tag on the end of every command, eg ":27.09.3"  
  
Step2:  
Afterwards change the tag in the yaml Manifest "trident-create-operator-and-orchestretor.yaml" in the day2 directory.
```text
Section Operator Deployment:
image: storm4.ocp.polizei.test:5000/openshift/release/netapp/trident-operator:27.09.3

Section TridentOrchestrator:
tridentImage: storm4.ocp.polizei.test:5000/openshift/release/netapp/trident:27.09.3
```

Step3:  
Apply the changed "yaml" file:  
```text
#oc apply -f trident-create-operator-and-orchestretor.yaml
```
#### NetApp, create a Volume and assign

```text
NetApp Storage in CoE!
User:      admin
Pass:      ********
```

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
/var/poc-berlin/day2

#### Apply the 3 Trident YAML Manifests

```text
#oc apply -f trident-secret.yaml
```

Explanation:
Securely stores the ONTAP administrator credentials (username vsadmin-pocpb and
password) in the cluster, allowing Astra Trident to authenticate against your NetApp SVM
main.

```text
#oc apply -f trident-backend-config.yaml
```

Explanation:
Configures the logical storage backend connection for Trident. It tells the controller to use the
ontap-nas-economy driver, connect via the management LIF (10.32.97.3), target the SVM
main, and carve out space inside your parent volume ocp_nfs_pool_poc_pb.

```text
#oc apply -f trident-storage-class.yaml
```

Explanation:

Exposes the storage to your cluster users by defining a Kubernetes StorageClass
(netapp-nfs-economy). When users request a PVC using this class, Trident automatically
handles the background mounting and qtree creation.

### NFS Storage (Optional!)

  - Create NDS on Storm4, quick and dirty
```text
#mkdir -p /var/nfs/ocp-pv1 && sudo chmod 777 /var/nfs/ocp-pv1
#echo "/var/nfs/ocp-pv1 192.168.60.0/24(rw,sync,no_root_squash)" | sudo tee -a /etc/exports
```

  - Create Storage Class Roles ect….
```text
#oc apply -f /var/poc-berlin/day2/nfs-provisioner.yaml
#oc adm policy add-scc-to-user hostmount-anyuid -z nfs-client-provisioner -n nfs-provisioner
```
  - Deploy the Provisioner
```text
#oc apply -f /var/poc-berlin/day2/nfs-deployment.yaml
```

  - Patch Storageclass

```text
#oc patch storageprofiles.cdi.kubevirt.io nfs-dynamic --type=merge -p '{"spec":{"claimPropertySets": [{"accessModes":["ReadWriteMany"], "volumeMode":"Filesystem"}]}}'
#Set Default for Cluster in the UI!
```

# Change internal OCP Registry (Ephemeral to Persistence)
[URL: Changing Internal OpenShift Registry](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/registry/setting-up-and-configuring-the-registry#configuring-registry-storage-baremetal)  
  
### Check out the Image Operator
```text
You will see, state is: "Management State: Removed" - so, no PVC is attached, it is ephemeral. 
#oc describe configs.imageregistry.operator.openshift.io
```
There are Pods for that Registry in Namespace "openshift-image-registry"  
```text
#oc get pods -n openshift-image-registry
```

### Create PVC "storage-registry
Namespace: openshift-image-registry  
Storage Class: nfs-dynamic
Size: 100 Gi  
Mode: RWX

### Finally, change Registry Deployment 
```text
#oc project openshift-image-registry

Go and change the "spec" section!
#oc edit configs.imageregistry.operator.openshift.io cluster
spec:
  managementState: Managed
  storageClassName: nfs-dynamic # Desired Storage Class!
  storage:
    pvc:
      claim: "storage-registry"
```
# Networks in Kubevirt

#### VM Network 1 - NNCP & NAD
```text
External Net via VLANID40 + DHCP via DNSMASQ in libvirt on storm4 (192.168.70.0/24) -
DHCP is external!
Check Netname in KVM: virsh net-info --network vtn-net
```
```text
-------------------------------
NNCP:             NNCP - /var/poc-berlin/day2/nncp-vlan40.yaml
NAD:              NAD  - /var/poc-berlin/day2/nad-vlan40.yaml
```

#### VM Network 2 - Internal for VM’s, NAD
```text
Just one NAD for an internal Network (East-West) so that VM’S can talk to each other:
NAD Name:
nad-internal-vm
```
# External Identity Provider htpasswd

[OCP Docu - Configuring identity providers](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/authentication_and_authorization/configuring-identity-providers)

#### Requirements htpasswd

- htpasswd Binary on the Bastion Host
```text
#sudo dnf install httpd-tools
```

#### Create a htpasswd file

/var/poc-berlin/day2
```text
#htpasswd -c -B -b /tmp/htpasswd wmarx *********
#htpasswd -B -b /tmp/htpasswd sabrina *********
```

#### Create Secret / Credentials in OCP

```text
#oc create secret generic htpasswd-secret --from-file htpasswd=/var/poc-berlin/day2/htpasswd -n openshift-config
```

Extract the secret/htpasswd again locally - when you lost it:
```text
#oc extract secret/htpasswd-secret -n openshift-config --to /var/poc-berlin/day2 --confirm
```

Then update the secret locally (after adding user with “htpassd -b -B….:

```text
#oc set data secret/htpasswd-secret --from-file htpasswd=/tmp/htpasswd -n openshift-config
```

#### Configure OAuth Provider

Step1:
Get the oauth Config
```text
#oc get oauth cluster -o yaml > oauth.yaml
```

Step2:
Change the specs in the oauth Config to add a provider
```text
spec:
  identityProviders:
  - htpasswd:
      fileData:
        name: htpasswd-secret
    mappingMethod: claim
    name: poc-pb-users
    type: HTPasswd
```

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

[URL: OCP Docu - Replacing Ingress Certs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/configuring-certificates)

#### Requirement

- Install Operator “cert-manager”

#### Step1: Create and issue certs

```text
Create a ClusterIssuer pointing to your internal enterprise Certificate Authority (CA).
#oc apply -f /var/poc-berlin/day2/cluster-issuer.yaml
```

What does that issue file do for us?
  1. Self-Signed Bootstrapper: We create a temporary, internal-only ClusterIssuer
      (selfsigned-root-issuer).
  2. Automated Root CA Certificate: We ask cert-manager to use that bootstrapper to
      generate a highly secure, dedicated Root CA key pair and save it in a Secret called
      poc-root-ca-secret.
  3. The Production CA Issuer: We create our production-grade ClusterIssuer
      (poc-trust-issuer) pointing to that automated secret.

Check the issuer (it has to be true!):
```text
#oc get issuer poc-trust-issuer -n openshift-ingress
```

#### Step2: Create the Wildcard Certificate Request
```text
Execute:     #oc apply -f /var/poc-berlin/day2/ingress-wildcard-certificate.yaml
Check:       #oc get certificate apps-wildcard-cert -n openshift-ingress
```
#### Step3: Update Ingress Controller

----------------------------------------------------------------------------
```text
#oc patch ingresscontroller default -n openshift-ingress-operator --type=merge -p '{"spec":{"defaultCertificate":{"name":"apps-wildcard-tls"}}}'
----------------------------------------------------------------------------
```
Check & Monitor the Process:
```text
#oc rollout status deployment/router-default -n openshift-ingress
```

#### Step4: replace new cert fo CO authentication operator

```text
Extract Active Root Certificate:
#oc get secret poc-root-ca-secret -n openshift-ingress -o jsonpath='{.data.tls\.crt}' | base64 --decode > active-root-ca.crt
Create Cluster-Wide ConfigMap:
#oc create configmap custom-ca --from-file=ca-bundle.crt=active-root-ca.crt -n openshift-config
Apply Custom CA to Cluster Proxy:
#oc patch proxy/cluster --type=merge -p '{"spec":{"trustedCA":{"name":"custom-ca"}}}'
Test:
#oc get proxy cluster -o jsonpath='{.spec.trustedCA}'
```

#### Step5: Trust this Cert in Chrome

Download the cert locally in the day2 directory!
```text
Again, as in the previous step - Cert Trust für *apps Ingress Certificate for Browser, but this time for our own cert.
#oc get secret poc-root-ca-secret -n openshift-ingress -o jsonpath='{.data.tls\.crt}' | base64 --decode > active-root-ca.crt
#sudo update-ca-trust
#sudo update-ca-trust extract
-------------------
Chrome Trust / Privacy and Security > Security > Manage Certs / Import CRT router-root-ca.crt
```
# Create two RHEL VM's in Namespace via the OCP Virt UI!
The following step creates two additional RHEL 9 virtual machines which can be used as test workloads inside OpenShift Virtualization.  

For this purpose, we use an existing RHEL 9 template as the base and create our own customized user template / blueprint from it.  

The goal is to keep the original RHEL 9 template unchanged and use a dedicated copy which can be adapted for this PoC.  

### 1. Create Namespace VM and Custom RHEL 9 Template via the UI
Start with an existing RHEL 9 template in OpenShift Virtualization and create a copy of it. Use existing system Template "
rhel9-server-small" and copy it with the name "rhel9-server-poc" in Namespace VM!  
The customized template will be adapted with:  
```text
- Create Namespace "VM"
- Copy Template "rhel9-server-small" 
- VM-specific settings required for this PoC
- The original RHEL 9 template remains untouched!!
```

#### 2. Adapt the Cloud-Init Configuration

Modify the Cloud-Init / user-data configuration of the copied RHEL 9 template.

This allows us to preconfigure the operating system during the first boot, for example:

- hostname
- user configuration (wmarx & redhat)
- SSH access
  * We gonna take out Test Lab Key in Storm4:
    ```text
    #oc create secret generic vm-ssh-key -n vm --from-file=key=/root/.ssh/id_ed25519.pub
    ```
    Now we can chose this SSH Key via the Web UI in the Template / or VM Manifest.  
- initial system settings
- additional RHEL configuration if required

The exact Cloud-Init configuration can be adapted independently for both virtual machines!

#### 3. Add the Virtual Networks to the Template
Attach the two virtual networks which were created in the previous steps of this documentation.  
The virtual machines should use the previously configured OpenShift Virtualization network definitions.  
For this PoC, the VM template is therefore extended with the required network interfaces before the virtual machines are created.  
This allows the VMs to communicate through the external and internal VM networks configured earlier.  
```text
Create the required virtual network interfaces (vm/nad-intern & vm/vlan40-net)
```

### 4. Create the Virtual Machines from the Template

Create two virtual machines from the customized RHEL 9 template in namespace via the UI!

```text
- Create two VM's (srvrhel1 & srvrhel2) / Create from Template
- Take the "User Template we created Above (rhel9-server-poc)
- Install in Namespace VM
- Start after Installation!
```
### 5. How to access these VM's now?
We have several possibilities to access a VM - straight via ssh, via the virtctl tool or the WEBUI,....  
Way1: virtctl
Download via the OC UI (Command Line Tools)
#wget --no-check-certificate https://hyperconverged-cluster-cli-download-openshift-cnv.apps.poc.ocp.berlin.test/amd64/linux/virtctl.tar.gz
```text
Jump to the RHEL9 console!
Approach1:
#virtctl console srvrhel01 -n vm
#To end the session: Ctrl + 5

Approach2:
#ssh wmarx@192.168.70.109 (The IP from the overlay libvirt host net, figure out in the UI)
```

## RHEL10 - Create a Template additional to the Boot Source

#### RHEL10 YAML Template Manifest
/var/poc-berlin/day2/template_rhel10.yaml  

Create the RHEL Template:  
```text
#oc apply -f /var/poc-berlin/day2/template_rhel10.yaml -n vm
```

# Create "not-rhel" templates!
The playbook `config_ocp-v-V3.yml` extends the default OpenShift Virtualization template catalog with additional operating systems which are not provided as ready-to-use templates in our environment.  
  
The playbook runs locally on the bastion host and uses the already configured `oc` CLI connection to create and modify OpenShift Virtualization resources.  

### Create additional VM Templates

The playbook downloads the upstream KubeVirt `common-templates` definition and uses the existing Ubuntu and Fedora templates as a technical base for additional operating systems. The DataVolume objects import the operating system images from external registry or HTTP sources, while the DataSource objects provide stable references to these images for the VM templates.  

For Ubuntu 22.04, the playbook also configures an automatic DataImportCron so that the base image can be refreshed periodically.  

The result is a set of ready-to-use non-RHEL templates with corresponding operating-system images that can be used directly to deploy virtual machines in OpenShift Virtualization.  
```text
It creates templates for:  
  
- Ubuntu 22.04  
- Debian 12  
- Debian Testing  
- FreeBSD 15.1  
- OpenSUSE 15.6
```  
Execute the Playbook in hetzner-stuff/day2_virt_install/templates:
```text
#ansible-playbook config_ocp-v-V3.yml
```
Test DV's & Templates:
```text
#oc get templates -n openshift | grep -Ei 'opensuse|freebsd|debian|ubuntu'
and:
#oc get dv -n openshift-virtualization-os-images | grep -Ei 'opensuse|freebsd|debian|ubuntu'
```
The downloaded KubeVirt templates are adjusted to use the OpenShift Virtualization image namespace: 
```text
#openshift-virtualization-os-images
```
And just in case we have to undo everything we did with the Playboook: "config_ocp-v-V3.yml"  
Execute the Playbook in hetzner-stuff/day2_virt_install/templates:  
```text
#ansible-playbook cleanup-virt.yaml
```

# Create Windows Machines!

### Architecture / Basic Relationship
Windows virtual machines in OpenShift Virtualization are deployed using the same storage model as the Linux templates described above.  

Instead of attaching an installation ISO or a manually prepared disk every time, we maintain a **Golden Image** for our Windows Versions and reference it through CDI objects.  

The basic relationship is:  

```text
Container Disk / Image
        |
        v
   DataVolume
        |
        v
       PVC
        |
        v
   DataSource
        |
        v
   VM Template
        |
        v
 Virtual Machine
```
### 1. DataVolume, PVC and DataSource

The DataVolume is responsible for importing or cloning an operating system image through CDI.  
After the import, the actual disk data is stored inside a PersistentVolumeClaim (PVC).  
The DataSource provides a stable logical reference to this PVC and can therefore be referenced by VM templates.  

In simple terms:  
```text
DataVolume (DV):
Downloads or clones the operating system image and creates the required PVC.

PVC:
Contains the actual operating system disk / Golden Image.

DataSource (DS):
Provides a stable reference to the PVC.

VM Template:
Defines the VM configuration and references the corresponding DataSource.

Virtual Machine:
The final VM instance receives its own disk cloned from the Golden Image.
```
This allows us to deploy multiple identical Windows machines without manually reinstalling Windows for every VM.  

### 2. Windows Golden Images

The following Windows images are prepared in the namespace:  
```text
#openshift-virtualization-os-images  
```

The file used for this is:  
```text
Increase RAM for Importer Pods:  
hetzner-stuff/day2_virt_install/holler_gitlab hco-ram-increase.yaml

Check RAM Increase:  
#oc get hyperconvergeds.v1beta1.hco.kubevirt.io kubevirt-hyperconverged -n openshift-cnv -o yaml | grep -A10 resourceRequirements

Create Windows Data Volumes:   
hetzner-stuff/day2_virt_install/holler_gitlab/datavolumes_windows.yaml  
```

It provides images for:  
```text
Windows Server 2025    -> win2k25
Windows Server 2022    -> win2k22
Windows Server 2019    -> win2k19
Windows 10             -> win10
Windows 11             -> win11
```
Each operating system gets its own: 
```text
'DataVolume'
'DataSource' >> and requests a 64 GiB disk.
```  
The source images are retrieved from:
```text
quay.io/openshift-cnv/containerdisks
```

# Additional Worker Nodes (Optional!)

To enable OpenShift to automatically communicate with KVM, spin up new VMs, and register
them as worker nodes, you must configure a virtual out-of-band management layer using a
BMC emulator Tool like vbmc for KVM/libvirt.

### The Architecture: How OpenShift talks to KVM

To automate worker provisioning, the platform leverages the native OpenShift Machine API
and the BareMetal Operator (Metal3). The workflow is as follows:

    1. BareMetalHost (BMH) Custom Resource:
       You define the physical or virtual worker machines in OpenShift as BareMetalHost
       resources. This object contains the MAC address of the VM's boot interface and the
       Redfish API URL exposed by BMC vbmc.

    2. MachineSet Scaling:
       When you scale the MachineSet from 0 to 1 (or more), the Machine API controller
       generates a Machine request, claims an available BareMetalHost.

### Master nodes from unmanaged to managed

The reason the initial bare metal hosts (Control Plane) are showing as Unmanaged with No
power management in the console is due to a specific safety mechanism applied by the
Assisted Installer during the cluster deployment.

To prevent the cluster's internal Bare Metal Operator (BMO) from interfering with this active
installation process (such as triggering unexpected power cycles, hardware inspections, or
disk-cleaning steps while the nodes are actively writing to disk), it explicitly detaches the
hosts from BMO control

#### Create an empty VM Shell for the worker nodes later (Done above!)

Create two virtual machine (e.g., named ocp4-node4/5) on storm4.
- State:  
       Keep the VM completely powered off (in shut off state).
- Virtual Disk:  
       Attach a blank virtual disk (e.g., /var/lib/libvirt/images/ocp4-node4.qcow2) with a
       capacity matching your existing worker nodes.
- MAC Address:  
       Record the MAC address of the primary network interface that is bridged to your
       192.168.60.0/24 subnet (ocp-net)


#### Apply the BMC Secrets for the BMC Cards

Day2 directory:
/var/poc-berlin/day2
```text
#oc apply -f /var/poc-berlin/day2/bmc-secrets-node4_and_5.yaml
```
#### Patch the existing BMHs with BMC configuration

The following Resource we have to change:
```text
#oc get provisionings.metal3.io provisioning-configuration -o yaml
#oc apply -f /var/poc-berlin/day2/provisioning-configuration.yaml
--------------------------------------------------------------
spec:
 provisioningNetwork: Managed
 provisioningInterface: enp9s0              # Interface on masters connected to provisioning-net
 provisioningIP: 172.22.0.3                 # IP address assigned to enp9s0 on the master nodes
 provisioningNetworkCIDR: 172.22.0.0/24     # CIDR of the provisioning network
 provisioningDHCPRange: 172.22.0.10,172.22.0.100 # DHCP range for PXE discovery and booting
 provisioningMacAddresses: #PXE and DHCP from Ironic has to bind to the master "provisiong-network!
 - "52:54:00:02:2d:fd"                      # Node 1 provisioning MAC
 - "52:54:00:fb:3e:4b"                      # Node 2 provisioning MAC
 - "52:54:00:62:ba:2c"                      # Node 3 provisioning MAC     
 preProvisioningOSDownloadURLs: {}
 watchAllNamespaces: true
--------------------------------------------------------------
```

What does it:
```text
    1. provisioningNetwork: Managed: Tells the BareMetal Operator to actively run its own
       DHCP/TFTP servers to network-boot (PXE) your new workers.
    2. provisioningInterface enp9s0: every interface!: Binds the DHCP and TFTP services
       specifically to the isolated provisioning network interface on your master nodes.
    3. provisioningNetworkCIDR: 172.22.0.0/24: Defines the subnet range of our isolated
       network.
    4. provisioningIPRange: 172.22.0.10,172.22.0.100: Tells the internal Ironic service
       which dynamic IP addresses it can hand out to the new hosts while they are PXE
       booting and installing RHCOS.
```

### Verify Operator and DHCP/TFTP Health
```text
#oc get pods -n openshift-machine-api | grep -E "metal3|baremetal|ironic"
```

### Patch the existing BMH Hosts and create node4 & 5

```text
#oc apply -f /var/poc-berlin/day2/baremetalhosts_node4_and_5.yaml
```
#oc get bmh -n openshift-machine-api  
```text
Outcome should be:
Name:                                State:                              ONLINE:
ocp4-node4                           available                           true            
ocp4-node5                           available                           true            

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

/var/poc-berlin/day2/worker-machineset.yaml

```text
#oc apply -f worker-machineset.yaml
#oc get machines -n openshift-machine-api
#oc get nodes
#oc scale machineset poc-pdvzj-worker -n openshift-machine-api --replicas=2
```

In the case the Provisioning Provision is failing, check the boot order (you need the provision
Network from KVM on Place 1
```text
#oc annotate bmh ocp4-node4 reboot-trigger=$(date +%s) --overwrite -n openshift-machine-api
#oc annotate bmh ocp4-node5 reboot-trigger=$(date +%s) --overwrite -n openshift-machine-api
```

```text
Sets the power state for both nodes to "on" / VMs are powered on.
#oc patch bmh ocp4-node4 -n openshift-machine-api --type=merge -p '{"spec":{"online":true}}'
#oc patch bmh ocp4-node5 -n openshift-machine-api --type=merge -p '{"spec":{"online":true}}'
```

```text
Sets the power state for both nodes to "off" / VMs are powered off.
#oc patch bmh ocp4-node4 -n openshift-machine-api --type merge -p '{"spec":{"online":false}}'
#oc patch bmh ocp4-node5 -n openshift-machine-api --type merge -p '{"spec":{"online":false}}'
```

```text
In Case the scale to zero command (#oc scale machineset pb-poc-kubevirt-worker --replicas=0) fails:
#oc patch bmh ocp4-node4 -n openshift-machine-api --type json -p '[{"op": "remove", "path": "/spec/consumerRef"}]'
#oc patch bmh ocp4-node5 -n openshift-machine-api --type json -p '[{"op": "remove", "path": "/spec/consumerRef"}]'
#oc patch machine pb-poc-kubevirt-worker-p69q2 -n openshift-machine-api --type json -p '[{"op": "remove", "path": "/metadata/finalizers"}]'
#oc patch machine pb-poc-kubevirt-worker-xtrbf -n openshift-machine-api --type json -p '[{"op": "remove", "path": "/metadata/finalizers"}]'
```

Monitor the process & Log with Metal3 Provisioner
```text
Watch the Metal3 operator write the OS to the disks
#oc get bmh -n openshift-machine-api
#oc logs -n openshift-machine-api -l k8s-app=metal3 --tail=50
```

```text
Track the OpenShift-level machine resource state
#oc get machines -n openshift-machine-api
```

```text
And if we see “pending” CSR’s with
#oc get csr >> we have to approve them!
#oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs oc adm certificate approve
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
#oc patch bmh ocp4-node4 -n openshift-machine-api -p '{"metadata":{"finalizers":[]}}' --type=merge
```

```text
#oc patch bmh ocp4-node5 -n openshift-machine-api -p '{"metadata":{"finalizers":[]}}' --type=merge
#oc patch bmh ocp4-node5 -n openshift-machine-api --type json -p '[ {"op": "remove", "path": "/spec/consumerRef"}]'
#oc patch machine poc-pdvzj-worker-xxxxx -n openshift-machine-api --type merge -p
'{"metadata":{"finalizers":[]}}'
```
