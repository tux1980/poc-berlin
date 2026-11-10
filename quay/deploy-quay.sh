#!/usr/bin/env bash
# WARNING:
# Test/PoC environment only.
# Contains hard-coded lab credentials and Quay secret keys.
# Do not reuse this configuration for production.
set -euo pipefail

echo "=== [1/7] Vorbereitung Verzeichnisse und Rechte ==="
mkdir -p /var/poc-berlin/quay/{config,storage,storage/uploads,postgres-data}
chmod -R 777 /var/poc-berlin/quay/storage
chown -R 1001:0 /var/poc-berlin/quay/storage || true

# Erforderlich für Red Hat PostgreSQL (UID 26)
chown -R 26:26 /var/poc-berlin/quay/postgres-data
chmod 700 /var/poc-berlin/quay/postgres-data

echo "=== [2/7] SSL-Zertifikate hinterlegen ==="
cp /var/poc-berlin/certs/quay.crt /var/poc-berlin/quay/config/ssl.cert
cp /var/poc-berlin/certs/quay.key /var/poc-berlin/quay/config/ssl.key
chmod -R 755 /var/poc-berlin/quay/config
chmod 644 /var/poc-berlin/quay/config/ssl.cert /var/poc-berlin/quay/config/ssl.key

echo "=== [3/7] Podman-Netzwerk sicherstellen ==="
podman network exists quay-net || podman network create quay-net

echo "=== [4/7] PostgreSQL und Redis starten ==="
# PostgreSQL
if ! podman ps -a --format '{{.Names}}' | grep -q '^quay-postgres$'; then
  podman run -d --name quay-postgres \
    --restart=always \
    --net quay-net \
    -e POSTGRESQL_USER=quayuser \
    -e POSTGRESQL_PASSWORD=quaypass \
    -e POSTGRESQL_DATABASE=quay \
    -v /var/poc-berlin/quay/postgres-data:/var/lib/pgsql/data:Z \
    -p 5432:5432 \
    registry.redhat.io/rhel9/postgresql-13:latest
else
  podman start quay-postgres
fi

# Redis
if ! podman ps -a --format '{{.Names}}' | grep -q '^quay-redis$'; then
  podman run -d --name quay-redis \
    --restart=always \
    --net quay-net \
    -p 6379:6379 \
    registry.redhat.io/rhel9/redis-7:latest
else
  podman start quay-redis
fi

echo "Warte auf Datenbankverbindung..."
until podman exec -i quay-postgres pg_isready -U quayuser -d quay >/dev/null 2>&1; do
  sleep 1
done
podman exec -i quay-postgres psql -U quayuser -d quay -c 'CREATE EXTENSION IF NOT EXISTS pg_trgm;'

echo "=== [5/7] config.yaml erzeugen ==="
cat <<'CONF' > /var/poc-berlin/quay/config/config.yaml
SERVER_HOSTNAME: quay.ocp.berlin.test:8447
PREFERRED_URL_SCHEME: https
SETUP_COMPLETE: true

FEATURE_BUILD_SUPPORT: false
FEATURE_USER_CREATION: true
FEATURE_ANONYMOUS_ACCESS: false
FEATURE_GENERAL_OCI_SUPPORT: true
TESTING: false

SECRET_KEY: "750ed845f5ba6d74bddec66dacf75e3db2cd7e8d8a5c8a82a3d30e29c9625ada"
DATABASE_SECRET_KEY: "1bf569bfdc7ec53bc08eb4a6a5c614b6350501f729064a881bef5d8551857492"

DB_URI: "postgresql://quayuser:quaypass@192.168.60.1:5432/quay"

BUILDLOGS_REDIS:
  host: 192.168.60.1
  port: 6379

USER_EVENTS_REDIS:
  host: 192.168.60.1
  port: 6379

SUPER_USERS:
  - admin

FEATURE_MAILING: true
MAIL_SERVER: int-mx.corp.redhat.com
MAIL_PORT: 25
MAIL_USE_TLS: false
MAIL_USE_AUTH: false
MAIL_DEFAULT_SENDER: wmarx@redhat.com

DISTRIBUTED_STORAGE_PREFERENCE:
  - local_us
DISTRIBUTED_STORAGE_DEFAULT_LOCATIONS:
  - local_us
DISTRIBUTED_STORAGE_CONFIG:
  local_us:
    - LocalStorage
    - storage_path: /datastorage/registry
CONF

chmod 644 /var/poc-berlin/quay/config/config.yaml

echo "=== [6/7] Quay Application Container starten ==="
podman rm -f quay-app 2>/dev/null || true

podman run -d --name quay-app \
  --restart=always \
  --net quay-net \
  -p 8447:8443 \
  -v /var/poc-berlin/quay/config:/conf/stack:Z \
  -v /var/poc-berlin/quay/storage:/datastorage/registry:Z \
  registry.redhat.io/quay/quay-rhel9:v3.18.2 registry

echo "Warte, bis Quay bereit ist..."
for i in {1..45}; do
  if curl -k -s -I https://quay.ocp.berlin.test:8447/v2/ | grep -q "401"; then
    echo "Quay API antwortet sauber!"
    break
  fi
  sleep 2
done

echo "=== [7/7] Admin-User anlegen & Trust hinterlegen ==="
mkdir -p /etc/containers/certs.d/quay.ocp.berlin.test:8447
cp /var/poc-berlin/certs/quay.crt /etc/containers/certs.d/quay.ocp.berlin.test:8447/ca.crt

# Admin-User über Quays Model anlegen, bcrypt-Passwort setzen und direkt verifizieren
podman exec -i quay-app python3 -c "
from app import app
from data import model
import bcrypt

hashed = bcrypt.hashpw(b'redhat123', bcrypt.gensalt()).decode('utf-8')

with app.app_context():
    u = model.user.get_user('admin')
    if not u:
        u = model.user.create_user_noverify('admin', 'wmarx@redhat.com')
    u.password_hash = hashed
    u.verified = True
    u.enabled = True
    u.save()
    print('Admin-User initial angelegt und verifiziert.')
"

# SQL-Absicherung: alle erforderlichen Not-Null-Attribute und Flags konsolidieren
podman exec -i quay-postgres psql -U quayuser -d quay -c "
UPDATE \"user\" 
SET verified = true, 
    enabled = true, 
    robot = false 
WHERE username = 'admin';
" >/dev/null 2>&1 || true

echo "=========================================================="
echo "Quay Registry erfolgreich bereitgestellt!"
echo "URL: https://quay.ocp.berlin.test:8447"
echo "Login: admin / redhat123"
echo "=========================================================="
