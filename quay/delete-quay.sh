#!/usr/bin/env bash

echo "=== Quay Cleanup gestartet ==="
echo

# Container löschen
for container in quay-app quay-postgres quay-redis; do
  if podman ps -a --format '{{.Names}}' | grep -qx "$container"; then
    if podman rm -f "$container" >/dev/null 2>&1; then
      echo "[OK] Container gelöscht: $container"
    else
      echo "[FEHLER] Container konnte nicht gelöscht werden: $container"
    fi
  else
    echo "[INFO] Container nicht vorhanden: $container"
  fi
done

echo

# Verzeichnisse löschen
for dir in \
  /var/poc-berlin/quay/postgres-data \
  /var/poc-berlin/quay/storage \
  /var/poc-berlin/quay/config \
  /etc/containers/certs.d/quay.ocp.berlin.test:8447
do
  if [ -e "$dir" ]; then
    if rm -rf "$dir"; then
      echo "[OK] Gelöscht: $dir"
    else
      echo "[FEHLER] Konnte nicht gelöscht werden: $dir"
    fi
  else
    echo "[INFO] Nicht vorhanden: $dir"
  fi
done

echo
echo "=== Quay Cleanup abgeschlossen ==="
