# K8s Multi-Cluster RAG

A demo environment that provisions a multi-cluster mesh on Azure Kubernetes Service (AKS), with network policy and observability via **Calico Cloud** or **Calico Enterprise**. The stack is driven by a single Makefile so you can bring up infrastructure, install Calico, and peer clusters from your machine.

**What it does:** Terraform creates three AKS clusters—**gateway-cluster**, **inference-cluster**, and **embedding-cluster**—then Calico (OSS base plus either Cloud or Enterprise) is installed and cluster mesh peering is configured. Kubeconfigs are written to `kubeconfigs/gateway-cluster.yaml`, `kubeconfigs/inference-cluster.yaml`, and `kubeconfigs/embedding-cluster.yaml`.

**Install options:** Use **`make all`** for the full Calico Cloud path (default), or **`make all-ce`** for the full Calico Enterprise path.

## Prerequisites

Ensure you have the following tools installed on your local machine:

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`)
- [Terraform](https://developer.hashicorp.com/terraform/downloads)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Make](https://www.gnu.org/software/make/)

## Configuration

1. **Environment Variables**:
   Create a `.env` file from the example template to store your credentials.

   ```bash
   cp .env.example .env
   ```

2. **Edit `.env`**:
   Open `.env` and configure your credentials.

   *   **Calico Cloud Key**: (Required) Needed to connect your clusters to Calico Cloud.
   *   **Azure Credentials**: (Optional) Not needed if you run `az login` before running commands.

   ```bash
   CALICO_CLOUD_KEY="<your-cloud-key>"
   # ARM_CLIENT_ID="..."  <-- Only needed if not using 'az login'
   ```

## Usage

This project uses a `Makefile` to manage the workflow. You can run the entire pipeline or specific stages.

### Quick Start

Run the entire workflow from start to finish using one of:

- **Calico Cloud** (default):
  ```bash
  make all
  ```
  This runs: backend → infra → kubeconfigs → Calico OSS → install Calico Cloud → license check → mesh.

- **Calico Enterprise**:
  ```bash
  make all-ce
  ```
  This runs: backend → infra → kubeconfigs → install Calico Enterprise → license check → mesh.

### Step-by-Step Execution

You can run individual steps if you need to debug or pause between stages:

1. **Setup Backend**: Create the Azure Storage spec for Terraform state.
   ```bash
   make setup-backend
   ```

2. **Infrastructure**: Provision AKS clusters using Terraform.
   ```bash
   make infra
   ```

3. **Kubeconfigs** (after infra): Kubeconfigs are written to `kubeconfigs/gateway-cluster.yaml`, `kubeconfigs/inference-cluster.yaml`, and `kubeconfigs/embedding-cluster.yaml`. Then install Calico (OSS):
   ```bash
   make kubeconfigs
   make install-calico
   ```

4. **Install Calico** (only needed if you are not using `make all` or `make all-ce`):

   - **Calico Cloud** (used by `make all`):
     ```bash
     make install-cc
     ```
   - **Calico Enterprise** (used by `make all-ce`):
     ```bash
     make install-ce
     ```

5. **Cluster Mesh**: Configure peering between the clusters.
   ```bash
   make mesh
   ```

6. **RAG application**: Apply or delete manifests from `rag-setup/` on each cluster (after `make kubeconfigs` and cluster mesh).
   ```bash
   make rag-apply              # apply to all clusters
   make rag-apply-gateway      # apply to gateway only
   make rag-apply-inference    # apply to inference only
   make rag-apply-embedding    # apply to embedding only
   make rag-delete             # delete from all clusters
   make rag-delete-gateway     # delete from gateway only
   make rag-delete-inference   # delete from inference only
   make rag-delete-embedding   # delete from embedding only
   ```


### Utilities

- **Clean**: Remove local kubeconfigs, `cluster-mesh-setup/`, and temp files (`calico-cloud-key.yaml`, `config.json`, `licensekey.yaml`).
  ```bash
  make clean
  ```

- **Destroy**: Run `make clean`, then tear down all Azure resources created by Terraform.
  ```bash
  make destroy
  ```

## Troubleshooting

- If `make infra` fails, ensure you are logged into Azure CLI (`az login`) or your `.env` credentials are correct.
- **GPU / vCPU quota (e.g. `ErrCode_InsufficientVCPUQuota` for Standard NCASv3_T4 in West US)**:
  - The inference cluster has an optional GPU node pool. If you hit quota in the default region (West US), either:
    1. **Use a different GPU VM size** you have quota for: in `environments/demo` set `aks_2_gpu_vm_size` (e.g. `Standard_NC6s_v3`) or pass `-var="aks_2_gpu_vm_size=Standard_NC6s_v3"`.
    2. **Use East US for the inference cluster**: set `vnet_2_location = "eastus"` (e.g. in a `terraform.tfvars` in `environments/demo`) so the cluster and GPU pool are created in a region where you have quota.
    3. **Disable the GPU pool** to bring up clusters first: set `aks_2_gpu_node_pool_enabled = false`, then request a [quota increase](https://learn.microsoft.com/en-us/azure/quotas/view-quotas) and re-enable.
- Logs for scripts are printed directly to the terminal.

## Requesting a quota increase from the CLI

You need **Azure CLI 2.54+** (the `quota` extension installs automatically). Run these from a terminal where you're logged in (`az login`). The first block sets your subscription and region so the commands work as-is.

**1. Set subscription and region (run once)**

```bash
SUB_ID=$(az account show --query id -o tsv)
REGION=westus   # or eastus, etc.
```

**2. See current compute quotas and usage**

```bash
# List all compute quotas for the region (find your VM family, e.g. "Standard NCASv3_T4 Family")
az quota list --scope "/subscriptions/${SUB_ID}/providers/Microsoft.Compute/locations/${REGION}" -o table

# Or list VM usage (shows current limit vs. used)
az vm list-usage --location "$REGION" -o table
```

**3. Request a higher vCPU limit for a VM family**

Use the **exact resource name** from step 2 (including spaces and casing). For NCASv3_T4 the name is `Standard NCASv3_T4 Family`. Example: set limit to **8** vCPUs.

```bash
az quota update \
  --resource-name "Standard NCASv3_T4 Family" \
  --scope "/subscriptions/${SUB_ID}/providers/Microsoft.Compute/locations/${REGION}" \
  --resource-type dedicated \
  --limit-object value=8
```

For other families, copy the name exactly as shown in `az quota list` (e.g. `standardDSv2Family`, `Standard NDASv4_A100 Family`). For a **new** quota, use `az quota create` with the same parameters.

**4. Check request status**

```bash
az quota request status list --scope "/subscriptions/${SUB_ID}/providers/Microsoft.Compute/locations/${REGION}"
```

Some quotas are **adjustable** and are approved quickly in the portal; others require a **support request**. If the CLI update fails or the quota is non-adjustable, use the [portal](https://portal.azure.com) → **Quotas** → **Compute** → select the quota → **New Quota Request** or **Create a support request**.
