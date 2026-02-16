# Inference stack: Gateway API, Inference Extension, kgateway, llm-d

These scripts install the LLM inference tier on the **inference cluster** (single cluster for now):

1. **Gateway API CRDs** (standard)
2. **Gateway API Inference Extension CRDs** (InferencePool, InferenceModel, etc.)
3. **kgateway** (CRDs + control plane with `inferenceExtension.enabled=true`)
4. **llm-d** stack via helmfile (gateway resource + EPP + vLLM model servers)

**Prerequisites:**

- `KUBECONFIG` set to inference cluster (e.g. `../kubeconfigs/inference-cluster.yaml` or export from parent Makefile).
- `kubectl`, `helm`, `helmfile`, `jq` installed.
- **HuggingFace token** in secret `llm-d-hf-token` in namespace `inference-vllm` with key `HF_TOKEN` (for gated models if needed).
- Kubernetes 1.29+.
- GPU node pool (or use CPU backend for llm-d; see llm-d docs).

**Order:**

1. Apply inference-cluster manifests first (so namespace `inference-vllm` and `embedding-vllm` exist).
2. Run `make install` from this directory (or from `rag-setup-vllm`: `make install-inference-stack`). This installs CRDs, kgateway, and llm-d (clones the llm-d repo into `.llm-d` and runs helmfile).

**After install:**

- The llm-d helmfile creates a gateway service. Its name depends on release/namespace (e.g. `infra-inference-vllm-inference-gateway`). Ensure `inference-cluster/manifests/10-inference-gateway-externalname.yaml` has `externalName` set to that service (e.g. `infra-inference-vllm-inference-gateway.inference-vllm.svc.cluster.local`). If different, update the manifest and re-apply.

**References:**

- [Gateway API install](https://gateway-api.sigs.k8s.io/guides/#installing-gateway-api)
- [Gateway API Inference Extension getting started](https://gateway-api-inference-extension.sigs.k8s.io/guides/)
- [llm-d inference-scheduling (kgateway)](https://llm-d.ai/docs/guide/Installation/inference-scheduling)
