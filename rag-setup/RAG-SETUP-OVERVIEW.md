# RAG Setup Overview

Brief reference for this repo’s RAG application running across three AKS clusters with Calico cluster mesh. Use this when asking other LLM queries about this setup.

## High-level architecture

- **Three clusters**: `gateway-cluster`, `inference-cluster`, `embedding-cluster`.
- **Cross-cluster access**: Calico cluster mesh + **federated services** (Tigera `federation.tigera.io/serviceSelector`). No Calico Ingress Gateway in this phase.
- **User entry point**: Gateway cluster exposes a **LoadBalancer** on the frontend; all API traffic is proxied to the RAG agent in the inference cluster.

## Per-cluster roles

### 1. Embedding cluster (`embedding` namespace)

- **Qdrant** (v1.7.4): Vector store; HTTP 6333, gRPC 6334; PVC for storage.
- **Embedding Ollama**: Serves **nomic-embed-text** for **batch** embedding (CronJob only). PVC for models.
- **Sample documents**: ConfigMap `sample-documents` with `doc1.txt`–`doc4.txt` (security, K8s, incident response, AI checklist).
- **Embedding CronJob** (`embedding-cronjob`): Runs every 5 min; Python script from ConfigMap `embedding-script`:
  - Creates Qdrant collection `documents` (cosine, 768 dims) if missing.
  - Reads `.txt` from `/documents` (mounted from `sample-documents`), embeds via embedding-ollama, upserts into Qdrant.
- **Services**: ClusterIP for Qdrant; **LoadBalancer** `qdrant-lb` for external/admin access to Qdrant.

### 2. Inference cluster (`inference` namespace)

- **Ollama (LLM)**: **phi3** for chat/completion; GPU node pool (`workload=llm`, toleration); PVC for models.
- **Ollama-embed**: **nomic-embed-text** only (CPU); used at **query time** for RAG. Separate from phi3.
- **LiteLLM**: Proxy in front of both Ollamas:
  - **phi3** → `ollama.inference.svc.cluster.local:11434`
  - **nomic-embed-text** → `ollama-embed.inference.svc.cluster.local:11434`
  - Exposes OpenAI-style `/v1/chat/completions` and `/v1/embeddings` on port 4000.
- **RAG agent** (Flask, Python):
  - **Embed**: Question → LiteLLM `/v1/embeddings` (nomic-embed-text).
  - **Retrieve**: Vector search against Qdrant in **embedding cluster** via **federated service** `qdrant-federated.embedding.svc.cluster.local`.
  - **Complete**: Context + question → LiteLLM `/v1/chat/completions` (phi3).
  - **Endpoints**: `POST /query` (RAG), `POST /chat` (proxy to LLM), `GET /health`, `GET /`.
- **Federated service (inference cluster)**: `qdrant-federated` in **embedding** namespace, selector `app == "qdrant"` — so RAG agent (in inference cluster) reaches Qdrant in embedding cluster over the mesh.

### 3. Gateway cluster

- **Namespaces**: `gateway` (frontend), plus **federated** namespaces `inference` and `embedding` (for federated service definitions only; no workloads).
- **Federated service**: `rag-agent` in **inference** namespace, selector `app == "rag-agent"` — so gateway can reach RAG agent in inference cluster.
- **Frontend**: Nginx serving static `index.html` (ConfigMap); **single route** `/api/rag/` → proxy to `rag-agent.inference.svc.cluster.local` (strip `/api/rag` prefix). All LLM and RAG traffic goes through the RAG agent; frontend never talks to LiteLLM or Qdrant directly.
- **Service**: `frontend` LoadBalancer (port 80) — user hits this to get UI and call `/api/rag/query` and `/api/rag/chat`.

## Data flow (summary)

1. **Batch indexing (embedding cluster)**: CronJob → embedding-ollama (nomic-embed-text) → Qdrant collection `documents`.
2. **RAG query**: User → Gateway (LoadBalancer) → Nginx `/api/rag/query` → RAG agent (inference) → LiteLLM embed → Qdrant (embedding, via federated) → LiteLLM completion (phi3) → response.
3. **Chat**: User → Gateway → Nginx `/api/rag/chat` → RAG agent → LiteLLM `/v1/chat/completions` (phi3).

## Apply/delete

From repo root:

- `make rag-apply` / `make rag-apply-gateway` | `rag-apply-inference` | `rag-apply-embedding`
- `make rag-delete` (and per-cluster variants)

Kubeconfigs: `kubeconfigs/<cluster>.yaml`. Cluster mesh must be up (`make mesh`) before RAG works across clusters.

## Key file locations (manifests)

- **Gateway**: `gateway-cluster/manifests/` — namespaces, frontend (config, nginx, deployment, LoadBalancer), rag-agent federated service.
- **Inference**: `inference-cluster/manifests/` — namespaces, Ollama (phi3), ollama-embed (nomic-embed-text), LiteLLM config/deploy, RAG agent config/deploy/service, qdrant-federated service.
- **Embedding**: `embedding-cluster/manifests/` — namespace, Qdrant (deploy, PVC, services), embedding-ollama (deploy, PVC), sample-documents, embedding-script ConfigMap, embedding CronJob, qdrant-lb.

## Tech stack (for context)

- **Vector DB**: Qdrant.
- **Embedding**: nomic-embed-text (768 dims, cosine).
- **LLM**: phi3 via Ollama.
- **Proxy**: LiteLLM (OpenAI-compatible API).
- **RAG app**: Flask (Python); calls LiteLLM and Qdrant.
- **Mesh**: Calico cluster mesh; federated services for cross-cluster DNS and traffic.
