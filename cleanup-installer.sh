#!/bin/bash
set -e

INSTALLER_DIR="/var/poc-berlin/installer"
IMAGE_DIR="/var/lib/libvirt/images"
NODES=("ocp4-node1" "ocp4-node2" "ocp4-node3")
NODE_IPS=("192.168.60.11" "192.168.60.12" "192.168.60.13")

echo "--> 1. Lösche ALLER Installer-Artefakte (auch versteckte & Metadaten)..."
if [ -d "$INSTALLER_DIR" ]; then
    # Leert den Ordner radikal komplett, damit KEIN alter State überlebt
    find "$INSTALLER_DIR" -mindepth 1 -delete
fi

echo "--> 2. Stoppe VMs..."
for node in "${NODES[@]}"; do
    virsh destroy "${node}" 2>/dev/null || true
done

echo "--> 3. Erstelle frische 150GB Festplatten mit korrekten KVM-Rechten..."
for node in "${NODES[@]}"; do
    IMG_PATH="${IMAGE_DIR}/${node}.qcow2"
    rm -f "$IMG_PATH"
    qemu-img create -f qcow2 "$IMG_PATH" 150G
    
    # FIX: Berechtigungen für den QEMU-Hypervisor setzen!
    chown qemu:qemu "$IMG_PATH" 2>/dev/null || chown 107:107 "$IMG_PATH" 2>/dev/null || true
    chmod 660 "$IMG_PATH"
done

echo "--> 4. Entferne SSH Host-Keys..."
if [ -f ~/.ssh/known_hosts ]; then
    for ip in "${NODE_IPS[@]}"; do
        ssh-keygen -R "$ip" 2>/dev/null || true
    done
fi

echo "--> Reset vollständig und sauber abgeschlossen!"
