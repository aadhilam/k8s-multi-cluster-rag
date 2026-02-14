#!/bin/bash
# Usage: ./install-calico.sh <kubeconfig-path> <cluster-name>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

KUBECONFIG=$1
CLUSTER_NAME=$2

export KUBECONFIG


# Check if 'calico-enterprise' Helm release is already installed
if helm status calico -n tigera-operator > /dev/null 2>&1; then
  echo "Helm release 'calico' already exists in namespace 'tigera-operator'. Skipping installation."
  exit 0
fi

echo "Helm release 'calico' not found. Proceeding with installation..."

#Add the Calico helm repo
helm repo add projectcalico https://docs.tigera.io/calico/charts

# Perform the Helm install
helm install calico projectcalico/tigera-operator --version v3.29.1 \
  -f "${MANIFESTS_DIR}/${CLUSTER_NAME}-values.yaml" \
  --namespace tigera-operator \
  --create-namespace

echo "calico has been installed successfully."
