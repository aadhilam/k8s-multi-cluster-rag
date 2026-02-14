#!/bin/bash
# Exit on any error
set -e

# Function to display usage
usage() {
  echo "Usage: $0 [--context <context1> <context2> ...] [--kubeconfig <kubeconfig1> <kubeconfig2> ...]"
  exit 1
}

# Parse arguments
CONTEXTS=()
KUBECONFIGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --context)
      shift
      while [[ $# -gt 0 && ! $1 =~ ^-- ]]; do
        CONTEXTS+=("$1")
        shift
      done
      ;;
    --kubeconfig)
      shift
      while [[ $# -gt 0 && ! $1 =~ ^-- ]]; do
        KUBECONFIGS+=("$1")
        shift
      done
      ;;
    *)
      usage
      ;;
  esac
done

if [[ ${#CONTEXTS[@]} -eq 0 && ${#KUBECONFIGS[@]} -eq 0 ]]; then
  usage
fi

# Resolve relative kubeconfig paths to absolute so they still work after we cd into cluster dirs
for i in "${!KUBECONFIGS[@]}"; do
  k="${KUBECONFIGS[$i]}"
  if [[ "$k" != /* ]]; then
    KUBECONFIGS[$i]="$(cd "$(dirname "$k")" && pwd)/$(basename "$k")"
  fi
done

########################################
# Function to create main cluster folder
# and configuration manifests
########################################
create_main_cluster_resources() {
  local context="$1"      # context name (if provided)
  local kubeconfig="$2"   # kubeconfig file (if provided)
  local cluster_name="$3" # identifier for the cluster (folder name)

  echo -e "\nProcessing main cluster: $cluster_name"

  # Create a folder for the cluster
  mkdir -p "$cluster_name"
  cd "$cluster_name"

  # Apply manifests for federation
  echo "Applying federation manifests..."
  kubectl --context="$context" --kubeconfig="$kubeconfig" apply -f https://downloads.tigera.io/ee/v3.19.4/manifests/federation-remote-sa.yaml
  kubectl --context="$context" --kubeconfig="$kubeconfig" apply -f https://downloads.tigera.io/ee/v3.19.4/manifests/federation-rem-rbac-kdd.yaml

  # Create Service Account Token
  echo "Creating Service Account Token..."
  kubectl --context="$context" --kubeconfig="$kubeconfig" apply -f - <<EOF
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: tigera-federation-remote-cluster
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: "tigera-federation-remote-cluster"
EOF

  # Save the Service Account Secret manifest
  echo "Saving the Service Account Secret manifest..."
  kubectl --context="$context" --kubeconfig="$kubeconfig" get secret tigera-federation-remote-cluster -n kube-system -o yaml | grep -v "creationTimestamp" > "tigera-federation-remote-cluster-secret.yaml"

  # Retrieve token and certificate-authority-data
  local token
  token=$(kubectl --context="$context" --kubeconfig="$kubeconfig" describe secret tigera-federation-remote-cluster -n kube-system | grep "^token:" | awk '{print $2}')

  local ca_data
  ca_data=$(kubectl --context="$context" --kubeconfig="$kubeconfig" config view --flatten --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

  local server
  if [[ -n "$context" ]]; then
    server=$(kubectl --context="$context" config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  elif [[ -n "$kubeconfig" ]]; then
    server=$(kubectl --kubeconfig="$kubeconfig" config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  fi

  # Create a dedicated kubeconfig file for this cluster
  echo "Creating config file for $cluster_name..."
  cat <<EOF > "$cluster_name-config.yaml"
apiVersion: v1
kind: Config
users:
- name: tigera-federation-remote-cluster
  user:
    token: $token
clusters:
- name: tigera-federation-remote-cluster
  cluster:
    certificate-authority-data: $ca_data
    server: $server
contexts:
- name: tigera-federation-remote-cluster-ctx
  context:
    cluster: tigera-federation-remote-cluster
    user: tigera-federation-remote-cluster
current-context: tigera-federation-remote-cluster-ctx
EOF

  # Test the newly created kubeconfig
  echo "Testing kubeconfig for $cluster_name..."
  kubectl --kubeconfig="$cluster_name-config.yaml" get nodes

  # Return to previous directory
  cd ..
}

########################################
# Function to create remote cluster
# configurations based on the main cluster
########################################
create_remote_cluster_resources() {
  local main_cluster_name="$1"  # Folder name for the main cluster
  local main_cluster_id="$2"    # The cluster identifier (context name or derived from kubeconfig)
  local main_kubeconfig="$3"    # kubeconfig file for the main cluster, if applicable

  echo -e "\nCreating remote cluster configurations for main cluster: $main_cluster_name"
  cd "$main_cluster_name"

  # Build an array of remote cluster identifiers
  local remote_clusters=()
  if [[ ${#CONTEXTS[@]} -gt 0 ]]; then
    remote_clusters=("${CONTEXTS[@]}")
  elif [[ ${#KUBECONFIGS[@]} -gt 0 ]]; then
    for kube in "${KUBECONFIGS[@]}"; do
      cluster_name=$(kubectl --kubeconfig="$kube" config view --minify -o jsonpath='{.contexts[0].name}')
      remote_clusters+=("$cluster_name")
    done
  fi

  # Loop over each remote cluster and create configuration manifests
  for remote_cluster in "${remote_clusters[@]}"; do
    if [[ "$remote_cluster" != "$main_cluster_id" ]]; then
      local remote_folder="remote-cluster-$remote_cluster"
      mkdir -p "$remote_folder"

      echo "Creating remote cluster configurations for $remote_cluster..."

      # Create secret manifest (referencing the remote cluster's config)
      kubectl create secret generic remote-cluster-secret-$remote_cluster -n calico-system \
        --from-literal=datastoreType=kubernetes \
        --from-file=kubeconfig="../$remote_cluster/$remote_cluster-config.yaml" \
        --dry-run=client -o yaml | grep -v "creationTimestamp" > "$remote_folder/secret-$remote_cluster.yaml"

      # Create RBAC manifest
      cat <<EOF > "$remote_folder/rbac-$remote_cluster.yaml"
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: remote-cluster-secret-access-$remote_cluster
  namespace: calico-system
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["remote-cluster-secret-$remote_cluster"]
  verbs: ["watch", "list", "get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: remote-cluster-secret-access-$remote_cluster
  namespace: calico-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: remote-cluster-secret-access-$remote_cluster
subjects:
- kind: ServiceAccount
  name: calico-typha
  namespace: calico-system
EOF

      # Create RemoteClusterConfiguration manifest
      cat <<EOF > "$remote_folder/remote-cluster-$remote_cluster-config.yaml"
apiVersion: projectcalico.org/v3
kind: RemoteClusterConfiguration
metadata:
  name: $remote_cluster
spec:
  clusterAccessSecret:
    name: remote-cluster-secret-$remote_cluster
    namespace: calico-system
    kind: Secret
  syncOptions:
    overlayRoutingMode: Enabled
EOF
    fi
  done

  # Apply all remote cluster configurations after creation
  if [[ ${#CONTEXTS[@]} -gt 0 ]]; then
    for remote_cluster in "${remote_clusters[@]}"; do
      if [[ "$remote_cluster" != "$main_cluster_id" ]]; then
        echo "Applying remote cluster configurations for $remote_cluster..."
        kubectl --context="$main_cluster_id" apply -f "remote-cluster-$remote_cluster" --recursive
      fi
    done
  elif [[ ${#KUBECONFIGS[@]} -gt 0 ]]; then
    for remote_cluster in "${remote_clusters[@]}"; do
      if [[ "$remote_cluster" != "$main_cluster_id" ]]; then
        echo "Applying remote cluster configurations for $remote_cluster..."
        kubectl --kubeconfig="$main_kubeconfig" apply -f "remote-cluster-$remote_cluster" --recursive
      fi
    done
  fi

  cd ..
}

########################################
# Main Execution Steps
########################################

# All output goes under cluster-mesh-setup/
OUTPUT_DIR="cluster-mesh-setup"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"
echo "Creating cluster mesh setup in $(pwd)"

# Step 1: Create main cluster folders and configurations
# When using contexts
for context in "${CONTEXTS[@]}"; do
  create_main_cluster_resources "$context" "" "$context"
done

# When using kubeconfig files
for kubeconfig in "${KUBECONFIGS[@]}"; do
  cluster_name=$(kubectl --kubeconfig="$kubeconfig" config view --minify -o jsonpath='{.contexts[0].name}')
  create_main_cluster_resources "" "$kubeconfig" "$cluster_name"
done

# Step 2: Create remote cluster folders and configurations
# When using contexts
for context in "${CONTEXTS[@]}"; do
  create_remote_cluster_resources "$context" "$context" ""
done

# When using kubeconfig files
for kubeconfig in "${KUBECONFIGS[@]}"; do
  cluster_name=$(kubectl --kubeconfig="$kubeconfig" config view --minify -o jsonpath='{.contexts[0].name}')
  create_remote_cluster_resources "$cluster_name" "$cluster_name" "$kubeconfig"
done

echo -e "\nCluster federation setup complete."