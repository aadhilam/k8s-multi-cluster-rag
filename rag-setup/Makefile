# RAG application manifests – apply to gateway, inference, and embedding clusters
# Run from repo root: make -C rag-setup apply-all
# Or use root Makefile: make rag-apply

SHELL := /bin/bash
# Kubeconfigs dir relative to repo root (default when invoked via make -C rag-setup)
KUBECONFIG_DIR ?= ../kubeconfigs

CLUSTERS := gateway-cluster inference-cluster embedding-cluster

.PHONY: help apply-all apply-gateway apply-inference apply-embedding delete-all delete-gateway delete-inference delete-embedding

help: ## Show RAG apply/delete targets
	@echo 'RAG setup – apply or delete manifests on clusters'
	@echo ''
	@echo 'Apply:'
	@echo '  apply-all       Apply manifests to all three clusters'
	@echo '  apply-gateway   Apply to gateway-cluster only'
	@echo '  apply-inference Apply to inference-cluster only'
	@echo '  apply-embedding Apply to embedding-cluster only'
	@echo ''
	@echo 'Delete:'
	@echo '  delete-all       Delete RAG manifests from all clusters'
	@echo '  delete-gateway   Delete from gateway-cluster only'
	@echo '  delete-inference Delete from inference-cluster only'
	@echo '  delete-embedding Delete from embedding-cluster only'
	@echo ''
	@echo 'Kubeconfigs: $(KUBECONFIG_DIR)/<cluster>.yaml'

apply-all: apply-gateway apply-inference apply-embedding ## Apply RAG manifests to all clusters

apply-gateway: ## Apply RAG manifests to gateway-cluster
	@echo "Applying RAG manifests to gateway-cluster..."
	@$(MAKE) _apply-cluster CLUSTER=gateway-cluster

apply-inference: ## Apply RAG manifests to inference-cluster
	@echo "Applying RAG manifests to inference-cluster..."
	@$(MAKE) _apply-cluster CLUSTER=inference-cluster

apply-embedding: ## Apply RAG manifests to embedding-cluster
	@echo "Applying RAG manifests to embedding-cluster..."
	@$(MAKE) _apply-cluster CLUSTER=embedding-cluster

# Internal: apply manifests for one cluster (federated services only; no Calico Ingress Gateway)
_apply-cluster:
	@KUBECONFIG="$(KUBECONFIG_DIR)/$(CLUSTER).yaml"; \
	if [ ! -f "$$KUBECONFIG" ]; then echo "Error: $$KUBECONFIG not found. Run 'make kubeconfigs' from repo root."; exit 1; fi; \
	echo "  -> $(CLUSTER)/manifests"; \
	kubectl --kubeconfig="$$KUBECONFIG" apply -f "$(CLUSTER)/manifests" --recursive

delete-all: delete-gateway delete-inference delete-embedding ## Delete RAG manifests from all clusters

delete-gateway: ## Delete RAG manifests from gateway-cluster
	@echo "Deleting RAG manifests from gateway-cluster..."
	@$(MAKE) _delete-cluster CLUSTER=gateway-cluster

delete-inference: ## Delete RAG manifests from inference-cluster
	@echo "Deleting RAG manifests from inference-cluster..."
	@$(MAKE) _delete-cluster CLUSTER=inference-cluster

delete-embedding: ## Delete RAG manifests from embedding-cluster
	@echo "Deleting RAG manifests from embedding-cluster..."
	@$(MAKE) _delete-cluster CLUSTER=embedding-cluster

# Internal: delete manifests for one cluster
_delete-cluster:
	@KUBECONFIG="$(KUBECONFIG_DIR)/$(CLUSTER).yaml"; \
	if [ ! -f "$$KUBECONFIG" ]; then echo "Error: $$KUBECONFIG not found."; exit 1; fi; \
	echo "  -> $(CLUSTER)/manifests"; \
	kubectl --kubeconfig="$$KUBECONFIG" delete -f "$(CLUSTER)/manifests" --recursive --ignore-not-found --timeout=60s
