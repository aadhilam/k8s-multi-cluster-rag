# RAG vLLM Setup Overview

Brief reference for the RAG application using **llm-d**, **vLLM**, and **kgateway** (K-agent). Same three-cluster topology as `rag-setup/` but with distinct namespaces (`*-vllm`) so both can coexist.

## Namespaces

- **gateway-vllm** (gateway cluster): frontend
- **inference-vllm** (inference cluster): RAG agent, ollama-embed, inference gateway (after llm-d install)
- **embedding-vllm** (embedding cluster): Qdrant, embedding-ollama, cronjob; (on inference cluster) federated service only

## Per-cluster roles

### Gateway cluster

- **Namespaces**: gateway-vllm, inference-vllm (federated), embedding-vllm (federated)
- **Frontend**: Nginx + static HTML; `/api/rag/` → proxy to **rag-agent.inference-vllm.svc.cluster.local**
- **Federated service**: rag-agent in inference-vllm namespace (selector app=rag-agent)
- **Service**: frontend LoadBalancer (port 80)

### Embedding cluster

- **Namespace**: embedding-vllm
- **Qdrant**, **embedding-ollama** (nomic-embed-text), **sample-documents** ConfigMap, **embedding-cronjob** (every 5 min), **qdrant-lb** LoadBalancer
- Same pattern as rag-setup; RAG agent reaches Qdrant via federated service from inference cluster

### Inference cluster

- **Namespaces**: inference-vllm, embedding-vllm (for qdrant-federated only)
- **ollama-embed**: nomic-embed-text for RAG query embeddings (CPU)
- **qdrant-federated**: in embedding-vllm namespace; selector app=qdrant (embedding cluster)
- **RAG agent**: embed via ollama-embed; retrieve via qdrant-federated; complete via **inference-gateway** (OpenAI /v1/chat/completions). inference-gateway is an ExternalName to the llm-d/kgateway gateway service.
- **Inference stack** (installed via scripts, not plain manifests): Gateway API CRDs, Inference Extension CRDs, **kgateway** (with inference extension), **llm-d** (helmfile: gateway + EPP + vLLM). After install, gateway service name must match `10-inference-gateway-externalname.yaml`.

## Data flow

1. **Batch indexing**: embedding cluster CronJob → embedding-ollama → Qdrant (documents collection).
2. **RAG query**: User → Gateway (frontend LoadBalancer) → Nginx `/api/rag/query` → RAG agent (inference-vllm) → ollama-embed (embed) → qdrant-federated (embedding-vllm) → inference-gateway (vLLM completion) → response.
3. **Chat**: User → frontend → RAG agent → inference-gateway (vLLM).

## Apply / delete

From repo root or from `rag-setup-vllm/`:

- `make -C rag-setup-vllm apply-all` or `apply-gateway` / `apply-inference` / `apply-embedding`
- `make -C rag-setup-vllm delete-all` (or per-cluster)
- **Inference stack** (CRDs + kgateway): `make -C rag-setup-vllm install-inference-stack` (requires KUBECONFIG=inference cluster). **llm-d** is installed manually from the llm-d repo; see `inference-cluster/scripts/README.md` and `make install-llmd-help`.

## Folder layout

- **gateway-cluster/manifests/** — namespaces, frontend, federated rag-agent service
- **inference-cluster/manifests/** — namespaces, ollama-embed, qdrant-federated, RAG agent, inference-gateway ExternalName
- **inference-cluster/scripts/** — Makefile to install Gateway API + Inference Extension CRDs, kgateway; README + install-llmd-help for llm-d
- **embedding-cluster/manifests/** — Qdrant, embedding-ollama, sample docs, cronjob, qdrant-lb
- **Makefile** — apply/delete per cluster; install-inference-stack target

## Kubeconfigs

Expects `../kubeconfigs/<cluster>.yaml` (or set KUBECONFIG_DIR). Cluster mesh must be up for cross-cluster traffic.
