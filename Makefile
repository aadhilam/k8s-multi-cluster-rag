# Makefile for AKS Cluster Mesh Demo
# Replicates the GitHub Actions workflow: deploy-calico-cloud.yaml

# Configuration
LOCATION ?= eastus
TF_STATE_RG ?= tfstate-rg
TF_STATE_STORAGE ?= cmtfstatestorage
TF_STATE_CONTAINER ?= tfstate

# Load environment variables from .env if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Default shell
SHELL := /bin/bash

.PHONY: all help setup-backend infra kubeconfigs install-calico check-api install-cc check-cc mesh clean destroy rag-apply rag-apply-gateway rag-apply-inference rag-apply-embedding rag-delete rag-delete-gateway rag-delete-inference rag-delete-embedding

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo
	@echo 'Targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

all: setup-backend infra kubeconfigs install-calico check-api install-cc check-cc mesh ## Run the full workflow sequentially

setup-backend: ## Create Azure resources for Terraform backend (tfstate)
	@echo "Creating Terraform backend resources..."
	az group create --name $(TF_STATE_RG) --location $(LOCATION)
	az storage account create --name $(TF_STATE_STORAGE) --resource-group $(TF_STATE_RG) --location $(LOCATION) --sku Standard_LRS
	az storage container create --name $(TF_STATE_CONTAINER) --account-name $(TF_STATE_STORAGE)

infra: ## Initialize and apply Terraform (creates AKS clusters)
	@echo "Setting up infrastructure..."
	@if [ -z "$$ARM_SUBSCRIPTION_ID" ]; then export ARM_SUBSCRIPTION_ID=$$(az account show --query id -o tsv); fi; \
	cd environments/demo && terraform init && terraform apply -auto-approve

kubeconfigs: ## Extract kubeconfigs from Terraform output
	@echo "Extracting kubeconfigs..."
	mkdir -p kubeconfigs
	cd environments/demo && terraform output -raw kubeconfig_1 > ../../kubeconfigs/gateway-cluster.yaml
	cd environments/demo && terraform output -raw kubeconfig_2 > ../../kubeconfigs/inference-cluster.yaml
	cd environments/demo && terraform output -raw kubeconfig_3 > ../../kubeconfigs/embedding-cluster.yaml
	@echo "Kubeconfigs saved to ./kubeconfigs/"

install-calico: ## Install Calico OSS on all clusters
	@echo "Installing Calico OSS..."
	chmod +x scripts/install-calico-oss.sh
	./scripts/install-calico-oss.sh ./kubeconfigs/gateway-cluster.yaml gateway-cluster
	./scripts/install-calico-oss.sh ./kubeconfigs/inference-cluster.yaml inference-cluster
	./scripts/install-calico-oss.sh ./kubeconfigs/embedding-cluster.yaml embedding-cluster

check-api: ## Check connectivity to API servers
	@echo "Checking API Servers..."
	chmod +x scripts/check-apiserver.sh
	@# Run in parallel and wait
	./scripts/check-apiserver.sh ./kubeconfigs/gateway-cluster.yaml gateway-cluster & \
	./scripts/check-apiserver.sh ./kubeconfigs/inference-cluster.yaml inference-cluster & \
	./scripts/check-apiserver.sh ./kubeconfigs/embedding-cluster.yaml embedding-cluster & \
	wait
	@echo "All API servers are reachable."

install-cc: ## Install/Upgrade to Calico Cloud
	@echo "Installing Calico Cloud..."
	chmod +x scripts/install-calico-cloud.sh
	./scripts/install-calico-cloud.sh ./kubeconfigs/gateway-cluster.yaml gateway-cluster
	./scripts/install-calico-cloud.sh ./kubeconfigs/inference-cluster.yaml inference-cluster
	./scripts/install-calico-cloud.sh ./kubeconfigs/embedding-cluster.yaml embedding-cluster

check-cc: ## Verify Calico Cloud license status
	@echo "Verifying Calico Cloud license..."
	chmod +x scripts/check-cc-license.sh
	@# Run in parallel and wait
	./scripts/check-cc-license.sh ./kubeconfigs/gateway-cluster.yaml gateway-cluster & \
	./scripts/check-cc-license.sh ./kubeconfigs/inference-cluster.yaml inference-cluster & \
	./scripts/check-cc-license.sh ./kubeconfigs/embedding-cluster.yaml embedding-cluster & \
	wait
	@echo "License checks passed."

mesh: ## specific_setup Cluster Mesh peering
	@echo "Setting up Cluster Mesh..."
	chmod +x scripts/cluster-mesh.sh
	./scripts/cluster-mesh.sh --kubeconfig ./kubeconfigs/gateway-cluster.yaml ./kubeconfigs/inference-cluster.yaml ./kubeconfigs/embedding-cluster.yaml

# RAG application – apply manifests from rag-setup/ to each cluster (requires kubeconfigs)
rag-apply: ## Apply RAG manifests to all clusters (gateway, inference, embedding)
	$(MAKE) -C rag-setup apply-all KUBECONFIG_DIR=../kubeconfigs

rag-apply-gateway: ## Apply RAG manifests to gateway-cluster only
	$(MAKE) -C rag-setup apply-gateway KUBECONFIG_DIR=../kubeconfigs

rag-apply-inference: ## Apply RAG manifests to inference-cluster only
	$(MAKE) -C rag-setup apply-inference KUBECONFIG_DIR=../kubeconfigs

rag-apply-embedding: ## Apply RAG manifests to embedding-cluster only
	$(MAKE) -C rag-setup apply-embedding KUBECONFIG_DIR=../kubeconfigs

# RAG application – delete manifests from clusters
rag-delete: ## Delete RAG manifests from all clusters
	$(MAKE) -C rag-setup delete-all KUBECONFIG_DIR=../kubeconfigs

rag-delete-gateway: ## Delete RAG manifests from gateway-cluster only
	$(MAKE) -C rag-setup delete-gateway KUBECONFIG_DIR=../kubeconfigs

rag-delete-inference: ## Delete RAG manifests from inference-cluster only
	$(MAKE) -C rag-setup delete-inference KUBECONFIG_DIR=../kubeconfigs

rag-delete-embedding: ## Delete RAG manifests from embedding-cluster only
	$(MAKE) -C rag-setup delete-embedding KUBECONFIG_DIR=../kubeconfigs

clean: ## Remove local kubeconfigs and temp files from make all / scripts
	rm -rf kubeconfigs cluster-mesh-setup
	rm -f calico-cloud-key.yaml config.json licensekey.yaml

destroy: clean ## Destroy Terraform infrastructure and remove all temp files
	@echo "Destroying infrastructure..."
	@if [ -z "$$ARM_SUBSCRIPTION_ID" ]; then export ARM_SUBSCRIPTION_ID=$$(az account show --query id -o tsv); fi; \
	cd environments/demo && terraform destroy -auto-approve
