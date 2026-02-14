################################################################################
# Resource Group
################################################################################
resource "azurerm_resource_group" "calico" {
  name     = var.resource_group_name
  location = var.rg_location
}

################################################################################
# VNET & Subnet 1
################################################################################
resource "azurerm_virtual_network" "vnet_1" {
  name                = "vnet-cluster-1"
  address_space       = var.vnet_1_address_space
  location            = var.vnet_1_location
  resource_group_name = azurerm_resource_group.calico.name
}

resource "azurerm_subnet" "subnet_1" {
  name                 = "subnet-cluster-1"
  virtual_network_name = azurerm_virtual_network.vnet_1.name
  resource_group_name  = azurerm_resource_group.calico.name
  address_prefixes     = var.vnet_1_subnet_cidr
}

################################################################################
# VNET & Subnet 2
################################################################################
resource "azurerm_virtual_network" "vnet_2" {
  name                = "vnet-cluster-2"
  address_space       = var.vnet_2_address_space
  location            = var.vnet_2_location
  resource_group_name = azurerm_resource_group.calico.name
}

resource "azurerm_subnet" "subnet_2" {
  name                 = "subnet-cluster-2"
  virtual_network_name = azurerm_virtual_network.vnet_2.name
  resource_group_name  = azurerm_resource_group.calico.name
  address_prefixes     = var.vnet_2_subnet_cidr
}

################################################################################
# VNET & Subnet 3 (NEW)
################################################################################
resource "azurerm_virtual_network" "vnet_3" {
  name                = "vnet-cluster-3"
  address_space       = var.vnet_3_address_space
  location            = var.vnet_3_location
  resource_group_name = azurerm_resource_group.calico.name
}

resource "azurerm_subnet" "subnet_3" {
  name                 = "subnet-cluster-3"
  virtual_network_name = azurerm_virtual_network.vnet_3.name
  resource_group_name  = azurerm_resource_group.calico.name
  address_prefixes     = var.vnet_3_subnet_cidr
}

################################################################################
# AKS Cluster 1
################################################################################
resource "azurerm_kubernetes_cluster" "aks_cluster_1" {
  name                = var.aks_cluster_1_name
  location            = var.vnet_1_location
  resource_group_name = azurerm_resource_group.calico.name
  kubernetes_version  = var.aks_kubernetes_version
  dns_prefix          = var.aks_1_dns_prefix

  default_node_pool {
    name           = var.aks_1_node_pool_name
    node_count     = var.aks_1_node_count
    vm_size        = var.aks_1_vm_size
    vnet_subnet_id = azurerm_subnet.subnet_1.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "none"
    service_cidr   = var.aks_1_service_cidr
    dns_service_ip = var.aks_1_dns_service_ip
    pod_cidr       = var.aks_1_pod_cidr
  }

  lifecycle {
    ignore_changes = all
  }

  depends_on = [azurerm_subnet.subnet_1]
}

################################################################################
# AKS Cluster 2
################################################################################
resource "azurerm_kubernetes_cluster" "aks_cluster_2" {
  name                = var.aks_cluster_2_name
  location            = var.vnet_2_location
  resource_group_name = azurerm_resource_group.calico.name
  kubernetes_version  = var.aks_kubernetes_version
  dns_prefix          = var.aks_2_dns_prefix

  default_node_pool {
    name           = var.aks_2_node_pool_name
    node_count     = var.aks_2_node_count
    vm_size        = var.aks_2_vm_size
    vnet_subnet_id = azurerm_subnet.subnet_2.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "none"
    service_cidr   = var.aks_2_service_cidr
    dns_service_ip = var.aks_2_dns_service_ip
    pod_cidr       = var.aks_2_pod_cidr
  }

  lifecycle {
    ignore_changes = all
  }

  depends_on = [azurerm_subnet.subnet_2]
}

# GPU node pool for inference cluster (optional)
resource "azurerm_kubernetes_cluster_node_pool" "inference_gpu" {
  count                 = var.aks_2_gpu_node_pool_enabled ? 1 : 0
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks_cluster_2.id
  vm_size               = var.aks_2_gpu_vm_size
  node_count            = var.aks_2_gpu_node_count
  vnet_subnet_id        = azurerm_subnet.subnet_2.id
  mode                  = "User"
}

################################################################################
# AKS Cluster 3 (NEW)
################################################################################
resource "azurerm_kubernetes_cluster" "aks_cluster_3" {
  name                = var.aks_cluster_3_name
  location            = var.vnet_3_location
  resource_group_name = azurerm_resource_group.calico.name
  kubernetes_version  = var.aks_kubernetes_version
  dns_prefix          = var.aks_3_dns_prefix

  default_node_pool {
    name           = var.aks_3_node_pool_name
    node_count     = var.aks_3_node_count
    vm_size        = var.aks_3_vm_size
    vnet_subnet_id = azurerm_subnet.subnet_3.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "none"
    service_cidr   = var.aks_3_service_cidr
    dns_service_ip = var.aks_3_dns_service_ip
    pod_cidr       = var.aks_3_pod_cidr
  }

  lifecycle {
    ignore_changes = all
  }

  depends_on = [azurerm_subnet.subnet_3]
}

################################################################################
# VNET Peering
################################################################################
# ---- Cluster 1 <-> Cluster 2 ----
resource "azurerm_virtual_network_peering" "vnet_peering_1_to_2" {
  name                      = "vnet-1-to-vnet-2"
  resource_group_name       = azurerm_resource_group.calico.name
  virtual_network_name      = azurerm_virtual_network.vnet_1.name
  remote_virtual_network_id = azurerm_virtual_network.vnet_2.id
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "vnet_peering_2_to_1" {
  name                      = "vnet-2-to-vnet-1"
  resource_group_name       = azurerm_resource_group.calico.name
  virtual_network_name      = azurerm_virtual_network.vnet_2.name
  remote_virtual_network_id = azurerm_virtual_network.vnet_1.id
  allow_virtual_network_access = true
}

# ---- Cluster 1 <-> Cluster 3 (NEW) ----
resource "azurerm_virtual_network_peering" "vnet_peering_1_to_3" {
  name                      = "vnet-1-to-vnet-3"
  resource_group_name       = azurerm_resource_group.calico.name
  virtual_network_name      = azurerm_virtual_network.vnet_1.name
  remote_virtual_network_id = azurerm_virtual_network.vnet_3.id
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "vnet_peering_3_to_1" {
  name                      = "vnet-3-to-vnet-1"
  resource_group_name       = azurerm_resource_group.calico.name
  virtual_network_name      = azurerm_virtual_network.vnet_3.name
  remote_virtual_network_id = azurerm_virtual_network.vnet_1.id
  allow_virtual_network_access = true
}

# ---- Cluster 2 <-> Cluster 3 (NEW) ----
resource "azurerm_virtual_network_peering" "vnet_peering_2_to_3" {
  name                      = "vnet-2-to-vnet-3"
  resource_group_name       = azurerm_resource_group.calico.name
  virtual_network_name      = azurerm_virtual_network.vnet_2.name
  remote_virtual_network_id = azurerm_virtual_network.vnet_3.id
  allow_virtual_network_access = true
}

resource "azurerm_virtual_network_peering" "vnet_peering_3_to_2" {
  name                      = "vnet-3-to-vnet-2"
  resource_group_name       = azurerm_resource_group.calico.name
  virtual_network_name      = azurerm_virtual_network.vnet_3.name
  remote_virtual_network_id = azurerm_virtual_network.vnet_2.id
  allow_virtual_network_access = true
}

################################################################################
# Outputs
################################################################################
output "kubeconfig_1" {
  sensitive = true
  value     = azurerm_kubernetes_cluster.aks_cluster_1.kube_config_raw
}

output "kubeconfig_2" {
  sensitive = true
  value     = azurerm_kubernetes_cluster.aks_cluster_2.kube_config_raw
}

output "kubeconfig_3" {
  sensitive = true
  value     = azurerm_kubernetes_cluster.aks_cluster_3.kube_config_raw
}
