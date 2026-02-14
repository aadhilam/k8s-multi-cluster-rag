################################################################################
# General (Existing)
################################################################################
variable "resource_group_name" {
  type        = string
  description = "Name of the Azure Resource Group."
  default     = "calico-clusters"
}

variable "rg_location" {
  type        = string
  description = "Location/region for the Resource Group."
  default     = "East US"
}

variable "vnet_1_location" {
  type        = string
  description = "Location for VNET 1 and AKS Cluster 1."
  default     = "East US"
}

variable "vnet_2_location" {
  type        = string
  description = "Location for VNET 2 and AKS Cluster 2."
  default     = "West US"
}

# -- NEW: VNET 3 location
variable "vnet_3_location" {
  type        = string
  description = "Location for VNET 3 and AKS Cluster 3."
  default     = "Central US"
}

variable "aks_kubernetes_version" {
  type        = string
  description = "Kubernetes version for the AKS clusters."
  default     = "1.32.1"
}

################################################################################
# VNETs & Subnets (Existing)
################################################################################
variable "vnet_1_address_space" {
  type        = list(string)
  description = "Address space for VNET 1."
  default     = ["10.10.0.0/16"]
}

variable "vnet_2_address_space" {
  type        = list(string)
  description = "Address space for VNET 2."
  default     = ["10.20.0.0/16"]
}

# -- NEW: VNET 3 address space
variable "vnet_3_address_space" {
  type        = list(string)
  description = "Address space for VNET 3."
  default     = ["10.30.0.0/16"]
}

variable "vnet_1_subnet_cidr" {
  type        = list(string)
  description = "Subnet CIDR(s) for VNET 1."
  default     = ["10.10.1.0/24"]
}

variable "vnet_2_subnet_cidr" {
  type        = list(string)
  description = "Subnet CIDR(s) for VNET 2."
  default     = ["10.20.1.0/24"]
}

# -- NEW: Subnet CIDR for VNET 3
variable "vnet_3_subnet_cidr" {
  type        = list(string)
  description = "Subnet CIDR(s) for VNET 3."
  default     = ["10.30.1.0/24"]
}

################################################################################
# AKS Cluster 1 Settings (Existing)
################################################################################
variable "aks_cluster_1_name" {
  type        = string
  description = "Name of AKS Cluster 1 (gateway)."
  default     = "gateway-cluster"
}

variable "aks_1_dns_prefix" {
  type        = string
  description = "DNS prefix for AKS Cluster 1."
  default     = "gateway"
}

variable "aks_1_node_pool_name" {
  type        = string
  description = "Node pool name for AKS Cluster 1."
  default     = "default"
}

variable "aks_1_node_count" {
  type        = number
  description = "Number of nodes in the default node pool for AKS Cluster 1."
  default     = 3
}

variable "aks_1_vm_size" {
  type        = string
  description = "VM size for the default node pool for AKS Cluster 1."
  default     = "Standard_DS2_v2"
}

variable "aks_1_service_cidr" {
  type        = string
  description = "Service CIDR for AKS Cluster 1."
  default     = "10.100.0.0/16"
}

variable "aks_1_dns_service_ip" {
  type        = string
  description = "DNS Service IP for AKS Cluster 1."
  default     = "10.100.0.10"
}

variable "aks_1_pod_cidr" {
  type        = string
  description = "Pod CIDR for AKS Cluster 1."
  default     = "10.200.0.0/16"
}

################################################################################
# AKS Cluster 2 Settings (Existing)
################################################################################
variable "aks_cluster_2_name" {
  type        = string
  description = "Name of AKS Cluster 2 (inference)."
  default     = "inference-cluster"
}

variable "aks_2_dns_prefix" {
  type        = string
  description = "DNS prefix for AKS Cluster 2."
  default     = "inference"
}

variable "aks_2_node_pool_name" {
  type        = string
  description = "Node pool name for AKS Cluster 2."
  default     = "default"
}

variable "aks_2_node_count" {
  type        = number
  description = "Number of nodes in the default node pool for AKS Cluster 2."
  default     = 3
}

variable "aks_2_vm_size" {
  type        = string
  description = "VM size for the default node pool for AKS Cluster 2."
  default     = "Standard_DS2_v2"
}

variable "aks_2_service_cidr" {
  type        = string
  description = "Service CIDR for AKS Cluster 2."
  default     = "10.101.0.0/16"
}

variable "aks_2_dns_service_ip" {
  type        = string
  description = "DNS Service IP for AKS Cluster 2."
  default     = "10.101.0.10"
}

variable "aks_2_pod_cidr" {
  type        = string
  description = "Pod CIDR for AKS Cluster 2."
  default     = "10.201.0.0/16"
}

# GPU node pool for inference cluster (Cluster 2)
variable "aks_2_gpu_node_pool_enabled" {
  type        = bool
  description = "Enable a dedicated GPU node pool on the inference cluster."
  default     = true
}

variable "aks_2_gpu_vm_size" {
  type        = string
  description = "VM size for the inference cluster GPU node pool. Use a size you have quota for (e.g. Standard_NC6s_v3). If you hit NCASv3_T4 quota in West US, try East US via vnet_2_location or a different SKU."
  default     = "Standard_NC6s_v3"
}

variable "aks_2_gpu_node_count" {
  type        = number
  description = "Number of nodes in the inference cluster GPU node pool."
  default     = 1
}

################################################################################
# AKS Cluster 3 Settings (NEW)
################################################################################
variable "aks_cluster_3_name" {
  type        = string
  description = "Name of AKS Cluster 3 (embedding)."
  default     = "embedding-cluster"
}

variable "aks_3_dns_prefix" {
  type        = string
  description = "DNS prefix for AKS Cluster 3."
  default     = "embedding"
}

variable "aks_3_node_pool_name" {
  type        = string
  description = "Node pool name for AKS Cluster 3."
  default     = "default"
}

variable "aks_3_node_count" {
  type        = number
  description = "Number of nodes in the default node pool for AKS Cluster 3."
  default     = 3
}

variable "aks_3_vm_size" {
  type        = string
  description = "VM size for the default node pool for AKS Cluster 3."
  default     = "Standard_DS2_v2"
}

variable "aks_3_service_cidr" {
  type        = string
  description = "Service CIDR for AKS Cluster 3."
  default     = "10.102.0.0/16"
}

variable "aks_3_dns_service_ip" {
  type        = string
  description = "DNS Service IP for AKS Cluster 3."
  default     = "10.102.0.10"
}

variable "aks_3_pod_cidr" {
  type        = string
  description = "Pod CIDR for AKS Cluster 3."
  default     = "10.202.0.0/16"
}
