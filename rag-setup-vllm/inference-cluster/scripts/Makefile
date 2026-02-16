# Install Gateway API + Inference Extension CRDs, kgateway, llm-d on inference cluster.
# Run with KUBECONFIG set to inference cluster (e.g. from rag-setup-vllm: make install-inference-stack).

NAMESPACE ?= inference-vllm
LLMD_REPO_DIR ?= $(dir $(lastword $(MAKEFILE_LIST))).llm-d
LLMD_REPO_URL ?= https://github.com/llm-d/llm-d
IGW_LATEST_RELEASE ?= $(shell curl -s https://api.github.com/repos/kubernetes-sigs/gateway-api-inference-extension/releases | jq -r '[.[] | select(.prerelease == false) | .tag_name] | sort | last')
KGTW_VERSION ?= v2.2.0-main

.PHONY: install install-crds install-kgateway install-llmd install-llmd-help post-install-fixups

# install = CRDs + kgateway + llm-d (clone repo and run helmfile) + fixups for standalone vLLM.
install: install-crds install-kgateway install-llmd post-install-fixups

# 1. Gateway API CRDs - install from standard channel if not already present
install-gateway-api-crds:
	@echo "Installing Gateway API CRDs (standard channel)..."
	kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# 2. Inference Extension CRDs
install-inference-extension-crds:
	@echo "Installing Gateway API Inference Extension CRDs (${IGW_LATEST_RELEASE})..."
	kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/$(IGW_LATEST_RELEASE)/manifests.yaml

install-crds: install-gateway-api-crds install-inference-extension-crds

# 3. kgateway (CRDs + control plane with inference extension)
install-kgateway:
	@echo "Installing kgateway CRDs and control plane (${KGTW_VERSION})..."
	helm upgrade -i --create-namespace -n kgateway-system --version $(KGTW_VERSION) kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds
	helm upgrade -i -n kgateway-system --version $(KGTW_VERSION) kgateway oci://cr.kgateway.dev/kgateway-dev/charts/kgateway --set inferenceExtension.enabled=true

# 4. llm-d stack: clone repo (if needed) and run helmfile. Requires: helmfile, git; optional: secret llm-d-hf-token for gated models.
# If helmfile is missing, print instructions and exit 0 so CRDs + kgateway install still "succeeds".
install-llmd:
	@echo "Installing llm-d stack (vLLM + gateway + EPP) in namespace $(NAMESPACE)..."
	@if ! command -v helmfile >/dev/null 2>&1; then \
		echo ""; \
		echo "helmfile not found. Install it (e.g. brew install helmfile, or https://github.com/helmfile/helmfile), then run:"; \
		echo "  make -C rag-setup-vllm/inference-cluster/scripts install-llmd"; \
		echo ""; \
		echo "Or run these steps manually:"; \
		$(MAKE) -s install-llmd-help; \
		exit 0; \
	fi
	@if [ ! -d "$(LLMD_REPO_DIR)/.git" ]; then \
		echo "Cloning llm-d repo into $(LLMD_REPO_DIR)..."; \
		git clone --depth 1 "$(LLMD_REPO_URL)" "$(LLMD_REPO_DIR)"; \
	else \
		echo "llm-d repo already at $(LLMD_REPO_DIR), skipping clone."; \
	fi
	@echo "Running helmfile apply -e kgateway in guides/inference-scheduling..."
	@cd "$(LLMD_REPO_DIR)/guides/inference-scheduling" && helmfile apply -e kgateway -n $(NAMESPACE)
	@if [ -f "$(LLMD_REPO_DIR)/guides/inference-scheduling/httproute.yaml" ]; then \
		echo "Applying httproute.yaml..."; \
		kubectl apply -f "$(LLMD_REPO_DIR)/guides/inference-scheduling/httproute.yaml" -n $(NAMESPACE); \
	else \
		echo "Note: httproute.yaml not found; apply it from the guide dir if required."; \
	fi
	@echo "Done. If gateway service name differs, update inference-cluster/manifests/10-inference-gateway-externalname.yaml externalName."

# 5. Post-install fixups: the llm-d modelservice (vLLM via llm-d-cuda image) fails CUDA init
#    on AKS T4 nodes. Scale it down; the standalone vLLM deployment in manifests/05-vllm-deployment.yaml
#    replaces it. Also remove the InferencePool-based HTTPRoute (replaced by manifests/11-vllm-direct-httproute.yaml).
post-install-fixups:
	@echo "Scaling down llm-d modelservice (replaced by standalone vLLM in manifests/)..."
	-kubectl scale deployment ms-inference-scheduling-llm-d-modelservice-decode -n $(NAMESPACE) --replicas=0 2>/dev/null || true
	@echo "Removing InferencePool-based HTTPRoute (replaced by manifests/11-vllm-direct-httproute.yaml)..."
	-kubectl delete httproute llm-d-inference-scheduling -n $(NAMESPACE) --ignore-not-found
	@echo "Restarting kgateway control plane and gateway proxy..."
	-kubectl rollout restart deployment kgateway -n kgateway-system 2>/dev/null || true
	@sleep 10
	-kubectl rollout restart deployment infra-inference-scheduling-inference-gateway -n $(NAMESPACE) 2>/dev/null || true
	@echo "Post-install fixups complete. Apply inference-cluster/manifests/ to deploy standalone vLLM + HTTPRoute."

# Print manual steps (e.g. if install-llmd fails or you prefer to run by hand).
install-llmd-help:
	@echo "=== llm-d stack (manual) ==="
	@echo "1. git clone https://github.com/llm-d/llm-d && cd llm-d"
	@echo "2. export NAMESPACE=$(NAMESPACE)"
	@echo "3. (Optional) kubectl create secret generic llm-d-hf-token -n $(NAMESPACE) --from-literal=HF_TOKEN=<token>"
	@echo "4. cd guides/inference-scheduling && helmfile apply -e kgateway -n \$${NAMESPACE}"
	@echo "5. kubectl apply -f httproute.yaml -n \$${NAMESPACE}"
	@echo "6. Update inference-cluster/manifests/10-inference-gateway-externalname.yaml externalName to match the gateway service."
