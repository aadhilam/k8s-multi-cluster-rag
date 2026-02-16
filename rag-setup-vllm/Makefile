# RAG-vLLM application: frontend, RAG agent, llm-d, vLLM, kgateway
# Namespaces: gateway-vllm, inference-vllm, embedding-vllm (coexist with rag-setup)
# Run from repo root: make -C rag-setup-vllm apply-all
# Or use root Makefile: make rag-apply-vllm (if wired in root Makefile)

SHELL := /bin/bash
KUBECONFIG_DIR ?= ../kubeconfigs

CLUSTERS := gateway-cluster inference-cluster embedding-cluster

.PHONY: help apply-all apply-gateway apply-inference apply-embedding delete-all delete-gateway delete-inference delete-embedding install-inference-stack

help: ## Show RAG-vLLM apply/delete targets
	@echo 'RAG-vLLM (llm-d, vLLM, kgateway) – apply or delete manifests'
	@echo ''
	@echo 'Apply:'
	@echo '  apply-all       Apply manifests to all three clusters'
	@echo '  apply-gateway   Apply to gateway-cluster only'
	@echo '  apply-inference Apply to inference-cluster only'
	@echo '  apply-embedding Apply to embedding-cluster only'
	@echo ''
	@echo 'Inference stack (kgateway + llm-d + vLLM):'
	@echo '  install-inference-stack  Run scripts to install CRDs, kgateway, llm-d (requires cluster access)'
	@echo ''
	@echo 'Delete:'
	@echo '  delete-all       Delete RAG-vLLM manifests from all clusters'
	@echo '  delete-gateway   Delete from gateway-cluster only'
	@echo '  delete-inference Delete from inference-cluster only'
	@echo '  delete-embedding Delete from embedding-cluster only'
	@echo ''
	@echo 'Kubeconfigs: $(KUBECONFIG_DIR)/<cluster>.yaml'

apply-all: apply-gateway apply-inference apply-embedding ## Apply to all clusters

apply-gateway:
	@echo "Applying RAG-vLLM manifests to gateway-cluster..."
	@$(MAKE) _apply-cluster CLUSTER=gateway-cluster

apply-inference:
	@echo "Applying RAG-vLLM manifests to inference-cluster..."
	@$(MAKE) _apply-cluster CLUSTER=inference-cluster

apply-embedding:
	@echo "Applying RAG-vLLM manifests to embedding-cluster..."
	@$(MAKE) _apply-cluster CLUSTER=embedding-cluster

_apply-cluster:
	@KUBECONFIG="$(KUBECONFIG_DIR)/$(CLUSTER).yaml"; \
	if [ ! -f "$$KUBECONFIG" ]; then echo "Error: $$KUBECONFIG not found. Run 'make kubeconfigs' from repo root."; exit 1; fi; \
	echo "  -> $(CLUSTER)/manifests"; \
	kubectl --kubeconfig="$$KUBECONFIG" apply -f "$(CLUSTER)/manifests" --recursive

delete-all: delete-gateway delete-inference delete-embedding

delete-gateway:
	@echo "Deleting RAG-vLLM manifests from gateway-cluster..."
	@$(MAKE) _delete-cluster CLUSTER=gateway-cluster

delete-inference:
	@echo "Deleting RAG-vLLM manifests from inference-cluster..."
	@$(MAKE) _delete-cluster CLUSTER=inference-cluster

delete-embedding:
	@echo "Deleting RAG-vLLM manifests from embedding-cluster..."
	@$(MAKE) _delete-cluster CLUSTER=embedding-cluster

_delete-cluster:
	@KUBECONFIG="$(KUBECONFIG_DIR)/$(CLUSTER).yaml"; \
	if [ ! -f "$$KUBECONFIG" ]; then echo "Error: $$KUBECONFIG not found."; exit 1; fi; \
	echo "  -> $(CLUSTER)/manifests"; \
	kubectl --kubeconfig="$$KUBECONFIG" delete -f "$(CLUSTER)/manifests" --recursive --ignore-not-found --timeout=60s

install-inference-stack: ## Install Gateway API + Inference Extension CRDs, kgateway, llm-d (inference-cluster)
	@echo "Installing inference stack (CRDs, kgateway, llm-d) on inference-cluster..."
	@KUBECONFIG_ABS="$(abspath $(KUBECONFIG_DIR)/inference-cluster.yaml)"; \
	if [ ! -f "$$KUBECONFIG_ABS" ]; then echo "Error: $$KUBECONFIG_ABS not found."; exit 1; fi; \
	export KUBECONFIG="$$KUBECONFIG_ABS"; \
	$(MAKE) -C inference-cluster/scripts install
