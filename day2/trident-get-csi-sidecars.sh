#!/usr/bin/env bash
set -euo pipefail

REGISTRY="storm4.ocp.polizei.test:5000/openshift/release"

echo "=== Mirroring Sidecars directly into ${REGISTRY} ==="

IMAGES=(
  "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.17.0|${REGISTRY}/csi-node-driver-registrar:v2.17.0"
  "registry.k8s.io/sig-storage/csi-provisioner:v6.3.0|${REGISTRY}/csi-provisioner:v6.3.0"
  "registry.k8s.io/sig-storage/csi-attacher:v4.11.0|${REGISTRY}/csi-attacher:v4.11.0"
  "registry.k8s.io/sig-storage/csi-resizer:v2.1.0|${REGISTRY}/csi-resizer:v2.1.0"
  "registry.k8s.io/sig-storage/csi-snapshotter:v8.6.0|${REGISTRY}/csi-snapshotter:v8.6.0"
  "docker.io/netapp/trident-autosupport:26.06|${REGISTRY}/trident-autosupport:26.06"
)

for pair in "${IMAGES[@]}"; do
  SRC="${pair%%|*}"
  DEST="${pair##*|}"
  echo "--> Mirroring ${SRC} -> ${DEST}"
  podman pull "${SRC}"
  podman tag "${SRC}" "${DEST}"
  podman push --tls-verify=false "${DEST}"
done
