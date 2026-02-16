# Deployment Plan: llm-d, vLLM, and kgateway on the Inference Cluster

This plan covers deploying **llm-d**, **vLLM**, and **kgateway** (KAgent) for a production-style LLM inference stack. All artifacts and references live under `rag-setup-vllm/`. No changes are made to the existing `rag-setup/` or other repo files.

**Terminology**: “KAgent” is taken to mean **kgateway** (the Gateway API + Inference Extension implementation). kgateway uses **agentgateway** (Envoy-based) as its data plane; you deploy kgateway and it brings the gateway (and inference-aware routing) to the cluster.

---

## 1. Scope: Inference cluster only

**Recommendation: Deploy vLLM, llm-d, and kgateway only on the inference cluster.**

| Component   | Cluster        | Role |
|------------|----------------|------|
| **vLLM**   | Inference only | Model server(s); GPU workload. |
| **llm-d**  | Inference only | Orchestrates vLLM + gateway + InferencePool/EPP; Helm/helmfile. |
| **kgateway** | Inference only | Gateway API implementation with Inference Extension; L7 routing to vLLM. |

**Why this is enough**

- LLM inference (vLLM) is GPU-heavy and belongs on the inference cluster.
- llm-d and kgateway are the **control and data plane for that inference tier**: they schedule and route requests to vLLM. They need to run where vLLM runs.
- Your **RAG agent** already runs on the inference cluster and today calls LiteLLM/Ollama. In the new setup it will call the **inference gateway** (exposed by kgateway/llm-d) instead of Ollama. No need to put llm-d or kgateway on the gateway or embedding cluster.
- **Gateway cluster**: unchanged; frontend still proxies to the RAG agent (inference cluster).
- **Embedding cluster**: unchanged; Qdrant + batch embedding stay there; RAG agent continues to use federated Qdrant for retrieval.

**Optional change later**: If you want the RAG agent to use vLLM for **embeddings** as well, you can add an embedding model to the vLLM/llm-d stack and point the RAG agent at the same gateway (or a dedicated route). The plan below focuses on **completion** (chat) first; embedding can be a follow-up.

---

## 2. High-level deployment order

Deployment is **inference-cluster-only** and follows this sequence:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  INFERENCE CLUSTER (single kubeconfig: inference-cluster)               │
├─────────────────────────────────────────────────────────────────────────┤
│  1. Prerequisites                                                        │
│     • Gateway API CRDs (standard)                                        │
│     • Namespace (e.g. llm-d or inference)                               │
│     • HuggingFace token secret                                          │
│     • (Optional) Monitoring stack for metrics                             │
│                                                                          │
│  2. Gateway API Inference Extension CRDs                                │
│     • InferencePool, InferenceModel, etc.                                │
│     • From kubernetes-sigs/gateway-api-inference-extension               │
│                                                                          │
│  3. kgateway (gateway + inference extension)                            │
│     • kgateway CRDs (Helm)                                               │
│     • kgateway control plane with inferenceExtension.enabled=true         │
│     • Uses agentgateway (Envoy) as data plane                            │
│                                                                          │
│  4. llm-d stack (Helmfile)                                               │
│     • Infra chart: Gateway resource + provider-specific config           │
│     • GAIE chart: InferencePool + EPP (Endpoint Picker)                  │
│     • Model server chart: vLLM deployment(s)                             │
│     • Deploy with -e kgateway so llm-d uses kgateway (not Istio)         │
└─────────────────────────────────────────────────────────────────────────┘
```

After step 4, the inference cluster exposes an **OpenAI-compatible** endpoint (via the Gateway) that the RAG agent (or any in-mesh client) can call for chat completions. vLLM runs as the backend; kgateway + EPP handle routing and optional load-aware/prefix-cache-aware scheduling.

---

## 3. Phase-by-phase plan

### Phase 0: Prerequisites (inference cluster)

- **Kubernetes**: 1.29+ (1.33+ recommended for full sidecar/init support if using llm-d’s patterns).
- **Tools** (on the machine that runs deploy): `kubectl`, `helm`, `helmfile`, `yq`, `git` (and optionally `jq`). See [llm-d client setup](https://github.com/llm-d/llm-d/blob/main/guides/prereq/client-setup/README.md).
- **Gateway API CRDs**: Install the standard [Gateway API](https://gateway-api.sigs.k8s.io/guides/#installing-gateway-api) CRDs (standard or experimental channel) on the inference cluster.
- **Namespace**: Create a dedicated namespace, e.g. `llm-d` (short names help avoid long hostnames). Export `NAMESPACE=llm-d` (or similar) for all steps.
- **HuggingFace token**: Create a Secret in that namespace (e.g. `llm-d-hf-token`) with key `HF_TOKEN` for pulling gated/private models (e.g. Llama) if needed. See [llm-d HuggingFace token](https://github.com/llm-d/llm-d/blob/main/guides/prereq/client-setup/README.md#huggingface-token).
- **Cluster access**: Use `KUBECONFIG=kubeconfigs/inference-cluster.yaml` (or your inference-cluster kubeconfig) for all commands.
- **Hardware**: GPU node pool (e.g. NVIDIA) with labels/taints as required by your vLLM workload; or follow llm-d’s CPU backend if you prefer a CPU-only test first.

**Deliverables in rag-setup-vllm**: A short **prereqs** doc or script that (1) checks Gateway API CRDs, (2) creates namespace and HF secret (placeholder or from env), (3) documents required tools and versions.

---

### Phase 1: Gateway API Inference Extension CRDs

- Install the Inference Extension CRDs (InferencePool, InferenceModel, InferenceObjective, etc.) so that kgateway and llm-d can use them.
- Use the official release manifest:
  - `kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${IGW_LATEST_RELEASE}/manifests.yaml`
- Set `IGW_LATEST_RELEASE` from the [releases](https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases) (e.g. latest non-prerelease).

**Deliverables**: A small script or doc under `rag-setup-vllm/` that sets the release variable and applies the manifest on the inference cluster (using the same kubeconfig/namespace as above).

---

### Phase 2: kgateway (with Inference Extension)

- **kgateway CRDs**: Install via Helm (e.g. from OCI):
  - `helm upgrade -i --create-namespace -n kgateway-system --version <KGTW_VERSION> kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds`
- **kgateway control plane**: Install kgateway with the Inference Extension enabled:
  - `helm upgrade -i -n kgateway-system --version <KGTW_VERSION> kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway --set inferenceExtension.enabled=true`
- Use a version that supports the Inference Extension (e.g. v2.2.0-main or the version recommended in [Gateway API Inference Extension – kgateway](https://gateway-api-inference-extension.sigs.k8s.io/guides/)).

**Deliverables**: A script or Helm command snippet in `rag-setup-vllm/` that installs kgateway CRDs and kgateway with `inferenceExtension.enabled=true`, plus a one-line note that agentgateway (Envoy) is deployed by kgateway as the data plane.

---

### Phase 3: llm-d stack (vLLM + InferencePool + Gateway resource)

- llm-d composes **infra** (gateway resource for the inference gateway), **GAIE** (InferencePool + EPP), and **model server** (vLLM) via **helmfile**.
- Use the **inference-scheduling** guide with the **kgateway** environment so that the gateway used is kgateway (not Istio):
  - From the [llm-d repo](https://github.com/llm-d/llm-d): `guides/inference-scheduling`
  - `helmfile apply -e kgateway -n ${NAMESPACE}`
- This assumes the Gateway control plane (kgateway) is already installed (Phase 2) and that Gateway API + Inference Extension CRDs are present (Phase 0–1).
- Adjust **replicas and resources** in the llm-d values to match your inference cluster (e.g. 2 GPUs for a small demo instead of 16). Use the values files referenced in [inference-scheduling](https://llm-d.ai/docs/guide/Installation/inference-scheduling) (e.g. `ms-inference-scheduling/values.yaml` for GPU/CPU).
- After deploy, apply the **HTTPRoute** as per llm-d’s guide (e.g. `kubectl apply -f httproute.yaml -n ${NAMESPACE}`), so that the Gateway routes to the InferencePool.

**Deliverables**: (1) A short doc in `rag-setup-vllm/` that points to llm-d’s inference-scheduling guide and lists exact steps: clone/use llm-d, set NAMESPACE, run `helmfile apply -e kgateway`, apply HTTPRoute. (2) Optional: a copied or symlinked `values` override file (e.g. for replica count or model name) if you don’t want to edit inside the llm-d repo.

---

### Phase 4: Verification and RAG integration

- **Verify**: List Helm releases in the chosen namespace; confirm Gateway has an address and Programmed=True; check InferencePool and vLLM pods are Running. Optionally send a test completion request to the gateway (OpenAI-style).
- **RAG agent**: Update the RAG agent (in a **separate** follow-up task, not in this plan’s file set) so that its completion URL points to the **inference gateway** (e.g. the Gateway’s ClusterIP or the Service that fronts it) instead of LiteLLM. The gateway exposes OpenAI-compatible `/v1/chat/completions` (and optionally `/v1/completions`). No change to gateway or embedding clusters for this step.

**Deliverables**: A short “Verification” section in the same doc as Phase 3, with example `kubectl` and `curl` commands. A note that RAG agent config change is out of scope for the initial artifact set but is the next step for full RAG + vLLM.

---

## 4. Suggested file layout under `rag-setup-vllm/`

All files for this plan live under `rag-setup-vllm/`. Suggested structure:

```
rag-setup-vllm/
├── DEPLOYMENT-PLAN.md          # This file
├── VALUE-PROPOSITION-VLLM-LLMD.md
├── docs/                       # Optional: extra notes
│   └── inference-cluster-notes.md
├── scripts/                    # Optional: automation
│   ├── 00-prereqs.sh           # Namespace, HF secret, Gateway API check
│   ├── 01-install-inference-extension-crds.sh
│   ├── 02-install-kgateway.sh
│   └── 03-deploy-llm-d-stack.sh # Wrapper around helmfile -e kgateway
└── values/                     # Optional: overrides for llm-d / vLLM
    └── ms-inference-scheduling-overrides.yaml
```

- **No duplication of existing RAG**: Do not copy or modify `rag-setup/` or gateway/embedding manifests. This folder is only for llm-d, vLLM, and kgateway on the inference cluster.
- **Scripts**: Can assume `KUBECONFIG` and `NAMESPACE` are set; optionally read from `.env` or a small config file under `rag-setup-vllm/`.

---

## 5. Summary and suggestions

- **Deploy only on the inference cluster**: vLLM, llm-d, and kgateway all run there. No changes to gateway or embedding clusters for this plan.
- **Order**: Prerequisites (Gateway API CRDs, namespace, HF token) → Inference Extension CRDs → kgateway (with inference extension) → llm-d stack with `-e kgateway`.
- **KAgent = kgateway**: You deploy kgateway; it uses agentgateway (Envoy) under the hood. No separate “KAgent” install.
- **RAG**: Keep the RAG agent on the inference cluster; after the stack is up, point it at the new inference gateway instead of LiteLLM for completions. Embedding can stay on the embedding cluster (existing Qdrant + Ollama) or be moved to vLLM later.
- **Model and size**: Start with the model/replica count from llm-d’s inference-scheduling (e.g. Qwen) and scale down replicas/GPU in values if your cluster is smaller; use CPU backend only for light testing.
- **Monitoring**: Enabling the monitoring stack recommended by llm-d (e.g. Prometheus/Grafana) in the inference cluster will help with tuning and debugging; it can be added in Phase 0 or after Phase 3.

This plan is ready to be implemented step by step; all related files and scripts should live under `rag-setup-vllm/` as above.

---

## 6. Implemented layout (this repo)

The deployment has been implemented under `rag-setup-vllm/` with the same folder hierarchy as `rag-setup/`:

- **Makefile** — `apply-all`, `apply-gateway`, `apply-inference`, `apply-embedding`, `delete-*`, `install-inference-stack` (runs inference-cluster/scripts to install CRDs + kgateway).
- **gateway-cluster/manifests/** — Namespaces (gateway-vllm, inference-vllm, embedding-vllm), frontend (config, nginx, deployment, LoadBalancer), federated rag-agent service.
- **embedding-cluster/manifests/** — Namespace embedding-vllm, Qdrant, embedding-ollama, sample-documents, embedding script ConfigMap, embedding CronJob, qdrant-lb.
- **inference-cluster/manifests/** — Namespaces (inference-vllm, embedding-vllm), ollama-embed (PVC, deployment, service), qdrant-federated, RAG agent (ConfigMap, deployment, service), inference-gateway ExternalName (points to llm-d gateway service after install).
- **inference-cluster/scripts/** — Makefile: `install` (Gateway API CRDs + Inference Extension CRDs + kgateway), `install-llmd-help` (manual llm-d steps). See README there.

Namespaces use the **-vllm** suffix (gateway-vllm, inference-vllm, embedding-vllm) so this setup can coexist with the original `rag-setup/`. See **RAG-SETUP-VLLM-OVERVIEW.md** for data flow and apply/delete usage.
