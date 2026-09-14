#!/bin/bash
set -e

WORKDIR="/var/poc-polizei"
INSTALL_DIR="${WORKDIR}/installer"
BINARY="${WORKDIR}/openshift-install"

# Safety Check: Ensure the required environment variables are exported before running
if [ -z "${PULL_SECRET}" ] || [ -z "${SSH_KEY}" ] || [ -z "${REGISTRY_CA}" ]; then
    echo "ERROR: Please ensure PULL_SECRET, SSH_KEY, and REGISTRY_CA are exported in your environment!"
    echo "Example:"
    echo "  export PULL_SECRET='\$(cat /path/to/pull-secret.json)'"
    echo "  export SSH_KEY='\$(cat ~/.ssh/id_rsa.pub)'"
    echo "  export REGISTRY_CA='\$(cat /var/poc-polizei/certs/domain.crt)'"
    exit 1
fi

echo "--> Bereinige Zielordner: ${INSTALL_DIR}"
rm -rf "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

echo "--> Verarbeite install-config.yaml (Ersetze Platzhalter & rücke CA ein)..."
# Use Python to safely substitute the variables without shell escaping issues
python3 -c "
import os

# Read the template
with open('${WORKDIR}/install-config.yaml', 'r') as f:
    content = f.read()

# Get environment variables
pull_secret = os.environ.get('PULL_SECRET', '').strip()
ssh_key = os.environ.get('SSH_KEY', '').strip()
registry_ca = os.environ.get('REGISTRY_CA', '')

# Indent each line of the CA certificate by exactly 2 spaces
indented_ca = '\n'.join('  ' + line if line.strip() else '' for line in registry_ca.splitlines())

# Perform safe replacements
content = content.replace('\${PULL_SECRET}', pull_secret)
content = content.replace('\${SSH_KEY}', ssh_key)
content = content.replace('\${REGISTRY_CA}', indented_ca)

# Write out the finalized install-config.yaml
with open('${INSTALL_DIR}/install-config.yaml', 'w') as f:
    f.write(content)
"

echo "--> Kopiere agent-config.yaml..."
cp "${WORKDIR}/agent-config.yaml" "${INSTALL_DIR}/agent-config.yaml"

echo "--> Erstelle Agent ISO..."
"${BINARY}" agent create image --dir="${INSTALL_DIR}"

echo "--> Fertig! ISO liegt unter: ${INSTALL_DIR}/agent.iso"
