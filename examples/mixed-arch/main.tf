terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 3.1.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "~> 2.2.0"
    }
    helm = {
      source = "hashicorp/helm"
      version = "~> 2.1.2"
    }
  }
  required_version = "~> 1.0"
}

provider "google" {
  # Configuration variables like project, region, zone should be set here
  # project = "your-gcp-project-id"
  # region  = "us-central1" # Or replace with your desired region
}

# Retrieve the project ID from the provider configuration
data "google_project" "current" {}

provider "kubernetes" {
  host                   = google_container_cluster.primary.endpoint
  token                  = google_container_cluster.primary.master_auth[0].token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = google_container_cluster.primary.endpoint
    token                  = google_container_cluster.primary.master_auth[0].token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

# The http data source can be kept as is if needed
# data "http" "my_ip" {
#   url = "http://ipv4.icanhazip.com"
# }

resource "random_string" "random" {
  length = 12
  upper = false
  number = false
  special = false
}

resource "random_password" "admin" {
  length = 14
  special = true
}

# GCP Naming & Metadata - Using variables and labels instead of Azure-specific modules
# Define variables for location, environment, product_name etc.
variable "region" {
  description = "GCP region for resources."
  type        = string
  default     = "us-central1" # Replace with your desired default region
}

variable "environment" {
  description = "Environment name (e.g., sandbox, dev, prod)."
  type        = string
  default     = "sandbox"
}

variable "product_name" {
  description = "Product name."
  type        = string
  default     = "myproduct" # Replace or derive from random_string
}

locals {
  # Use consistent labels for resources
  common_labels = {
    environment = var.environment
    product     = var.product_name == "myproduct" ? random_string.random.result : var.product_name
    managed_by  = "terraform"
  }
}

# GCP Networking: VPC and Subnets
# Replace azurerm_virtual_network and azurerm_subnet modules
resource "google_compute_network" "vpc" {
  name                    = "${local.common_labels.product}-vpc"
  auto_create_subnetworks = false # We will create subnets manually
  mtu                     = 1460

  labels = local.common_labels
}

resource "google_compute_subnetwork" "private" {
  name          = "${local.common_labels.product}-private-subnet"
  ip_cidr_range = "10.1.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  # The `role` and `purpose` attributes might be relevant depending on GKE networking needs,
  # e.g., specifying secondary ranges for GKE Pods/Services.
  # For a direct translation, we define a standard subnet.

  labels = local.common_labels
}

resource "google_compute_subnetwork" "public" {
  name          = "${local.common_labels.product}-public-subnet"
  ip_cidr_range = "10.1.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  labels = local.common_labels
}

# GCP Firewall Rules (equivalent of Azure NSG rules)
# Replace azurerm_network_security_rule
# We'll create rules to allow ingress to nodes based on tags.
# GKE nodes get network tags automatically, but custom tags are useful for fine-grained rules.
# We'll add custom tags to node pools and use those here.

resource "google_compute_firewall" "allow_http_to_web_nodes" {
  name    = "${local.common_labels.product}-allow-http"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"] # Allow HTTP traffic from anywhere (Load Balancer source is often specific range or health checks)

  # Target nodes with specific network tags added to the GKE node pools
  target_tags = [
    "${local.common_labels.product}-web-linux", # Tag for linuxweb pool
    "${local.common_labels.product}-web-windows" # Tag for winweb pool
  ]

  labels = local.common_labels
}

# GCP Kubernetes: GKE Cluster and Node Pools
# Replace azurerm_kubernetes_cluster module
resource "google_container_cluster" "primary" {
  name = "${local.common_labels.product}-gke"
  location = var.region
  # GCP Project is inherited from provider

  # Recommended: Enable VPC-native (alias IPs)
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "/19" # Range for pods
    services_ipv4_cidr_block = "/22" # Range for services
  }

  # GKE integrates with VPC networks
  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.private.id # Cluster control plane and default pool (if not removed)

  # Disable the default node pool to manage node pools separately
  remove_default_node_pool = true
  initial_node_count       = 1 # Can be low if remove_default_node_pool is true

  # Configure private endpoint if needed (equivalent to Azure Private Cluster)
  # private_cluster_config {
  #   enable_private_endpoint = true
  #   enable_private_nodes    = true
  #   master_ipv4_cidr_block  = "172.16.0.0/28"
  # }

  # Identity - GKE nodes use service accounts. Default is usually sufficient unless specific permissions needed.
  # node_config {
  #   service_account = "your-gcp-service-account-id"
  #   oauth_scopes    = ["cloud-platform"]
  # }

  # Windows admin user/password not configured on cluster level, but via NodePool config if needed or via standard K8s methods
  # auto_repair  = true
  # auto_upgrade = true

  labels = local.common_labels
}

resource "google_container_node_pool" "system" {
  name       = "${local.common_labels.product}-system-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 2 # Equivalent to Azure node_count

  node_config {
    machine_type = "e2-medium" # Equivalent to Standard_B2s (or adjust as needed)
    disk_size_gb = 20 # Default disk size
    oauth_scopes = [
      "cloud-platform" # Recommended for GKE nodes
    ]
    # Node pool should be in the private subnet as in Azure example
    subnetwork = google_compute_subnetwork.private.id
    # Add network tags for firewall rules if needed, though system pool might not need public ingress
    # tags = ["${local.common_labels.product}-system"]

    # Ensure GKE can assign Pod IPs from the cluster range
    # node_ip_config {
    #   ipv4_cidr_range = "" # Use default configured on cluster/subnet
    # }
    # linux_node_config {} # Default is Linux
  }

  # only_critical_addons_enabled not a direct node pool setting in GKE
  # This is typically a cluster-level configuration or managed via Node Taints/Labels.
  # You can add taints here to prevent non-critical pods from scheduling.
  # taints {
  #   key    = "CriticalAddonsOnly"
  #   value  = "true"
  #   effect = "NoSchedule"
  # }

  labels = local.common_labels # Labels for the node pool resource in GCP console
}

resource "google_container_node_pool" "linuxweb" {
  name     = "${local.common_labels.product}-linuxweb-pool"
  location = var.region
  cluster  = google_container_cluster.primary.name

  # enable_auto_scaling = true -> managed via autoscaling block
  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  node_config {
    machine_type = "e2-medium" # Equivalent to Standard_B2ms (or adjust as needed)
    disk_size_gb = 20
    oauth_scopes = [
      "cloud-platform"
    ]
    # Node pool should be in the public subnet as in Azure example
    subnetwork = google_compute_subnetwork.public.id
    # Add network tags for firewall rules (e.g., for the LB)
    tags = ["${local.common_labels.product}-web-linux"]

    # Add labels for Kubernetes node selectors
    labels = {
      nodepool = "linuxweb" # Custom label for k8s nodeSelector
    }
    # linux_node_config {} # Default is Linux
  }

  labels = local.common_labels
}

resource "google_container_node_pool" "winweb" {
  name     = "${local.common_labels.product}-winweb-pool"
  location = var.region
  cluster  = google_container_cluster.primary.name

  # enable_auto_scaling = true -> managed via autoscaling block
  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  node_config {
    machine_type = "n2-standard-4" # Equivalent to Standard_D4a_v4 (or adjust as needed)
    disk_size_gb = 50 # Windows nodes often need larger disks
    oauth_scopes = [
      "cloud-platform"
    ]
    # Node pool should be in the public subnet as in Azure example
    subnetwork = google_compute_subnetwork.public.id
    # Add network tags for firewall rules (e.g., for the LB)
    tags = ["${local.common_labels.product}-web-windows"]

    # Add labels for Kubernetes node selectors
    labels = {
      nodepool = "winweb" # Custom label for k8s nodeSelector
    }

    # Specify Windows OS type
    operating_system = "WINDOWS_LTSC" # Use the appropriate Windows image type
    # For Windows nodes requiring admin password access for troubleshooting (not recommended for normal operations)
    # windows_node_config {
    #   enable_serial_port = true
    # }
  }

  # GKE node pool OS type and labels are used instead of Azure's os_type and implicit agentpool label
  # taints might be used for OS separation if not using dedicated pools
  # taints {
  #   key    = "node.kubernetes.io/os"
  #   value  = "windows"
  #   effect = "NoSchedule"
  # }

  labels = local.common_labels
}


# Helm releases - can remain largely the same, adjusting node selectors
resource "helm_release" "nginx" {
  depends_on = [google_container_cluster.primary, google_container_node_pool.linuxweb] # Depend on the cluster and node pool creation
  name       = "nginx"
  chart      = "./helm_chart"

  # Configure namespace if needed, e.g., namespace = "default"

  set {
    name  = "name"
    value = "nginx"
  }

  set {
    name  = "image"
    value = "nginx:latest"
  }

  # Use the custom node label defined on the GKE node pool
  set {
    name  = "nodeSelector"
    value = yamlencode({ nodepool = "linuxweb" })
  }
}

resource "helm_release" "iis" {
  depends_on = [google_container_cluster.primary, google_container_node_pool.winweb] # Depend on the cluster and node pool creation
  name       = "iis"
  chart      = "./helm_chart"
  timeout    = 600 # Helm timeout in seconds

  # Configure namespace if needed, e.g., namespace = "default"

  set {
    name  = "name"
    value = "iis"
  }

  set {
    name  = "image"
    value = "mcr.microsoft.com/windows/servercore/iis:latest" # Use appropriate Windows IIS image
  }

  # Use the custom node label defined on the GKE node pool
  set {
    name  = "nodeSelector"
    value = yamlencode({ nodepool = "winweb" })
  }
}

# Kubernetes Service data sources - can remain the same to get LB IP
data "kubernetes_service" "nginx" {
  depends_on = [helm_release.nginx]
  metadata {
    name = "nginx"
    # Configure namespace if not 'default'
    # namespace = "default"
  }
}

data "kubernetes_service" "iis" {
  depends_on = [helm_release.iis]
  metadata {
    name = "iis"
    # Configure namespace if not 'default'
    # namespace = "default"
  }
}

# Outputs - Adapt to GCP context
output "nginx_url" {
  description = "URL for the Nginx service LoadBalancer."
  value       = "http://${data.kubernetes_service.nginx.status.0.load_balancer.0.ingress.0.ip}"
}

output "iis_url" {
  description = "URL for the IIS service LoadBalancer."
  value       = "http://${data.kubernetes_service.iis.status.0.load_balancer.0.ingress.0.ip}"
}

output "gke_login_command" {
  description = "Command to configure kubectl for the GKE cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${data.google_project.current.project_id}"
}