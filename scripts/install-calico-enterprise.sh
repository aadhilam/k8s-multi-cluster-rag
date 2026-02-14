#!/bin/bash
# Usage: ./install-calico.sh <kubeconfig-path> <cluster-name>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

KUBECONFIG=$1
CLUSTER_NAME=$2

export KUBECONFIG

# Apply StorageClass (repeated kubectl apply is typically idempotent).
kubectl apply -f "${MANIFESTS_DIR}/storageclass.yaml"

# Check if 'calico-enterprise' Helm release is already installed
if helm status calico-enterprise -n tigera-operator > /dev/null 2>&1; then
  echo "Helm release 'calico-enterprise' already exists in namespace 'tigera-operator'. Skipping installation."
  exit 0
fi

echo "Helm release 'calico-enterprise' not found. Proceeding with installation..."

# Download the Tigera operator chart
curl -O -L https://downloads.tigera.io/ee/charts/tigera-operator-v3.19.4-0.tgz

# Write image pull secret and license key to files
echo "$CALICO_PULL_SECRET" > config.json
echo "$CALICO_LICENSE_KEY" | base64 -d > licensekey.yaml

# Perform the Helm install
helm install calico-enterprise tigera-operator-v3.19.4-0.tgz \
  -f "${MANIFESTS_DIR}/${CLUSTER_NAME}-values.yaml" \
  --set-file imagePullSecrets.tigera-pull-secret=config.json,tigera-prometheus-operator.imagePullSecrets.tigera-pull-secret=config.json \
  --set-file licenseKeyContent=licensekey.yaml \
  --namespace tigera-operator \
  --create-namespace

echo "calico-enterprise has been installed successfully."
