#!/bin/bash
# Usage: ./install-calico.sh <kubeconfig-path> <cluster-name>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

KUBECONFIG=$1
CLUSTER_NAME=$2

export KUBECONFIG

#Add the Calico helm repo
helm repo add calico-cloud https://installer.calicocloud.io/charts --force-update

#Add the Calico Cloud custom resource definitions:
helm upgrade --install calico-cloud-crds calico-cloud/calico-cloud-crds \
--namespace calico-cloud \
--create-namespace

echo "$CALICO_CLOUD_KEY" | base64 -d > calico-cloud-key.yaml
kubectl apply -f calico-cloud-key.yaml

# Perform the Helm install of Calico Cloud
helm upgrade --install calico-cloud calico-cloud/calico-cloud \
--namespace calico-cloud \
-f "${MANIFESTS_DIR}/${CLUSTER_NAME}-cc-values.yaml"


echo "calico has been installed successfully."
