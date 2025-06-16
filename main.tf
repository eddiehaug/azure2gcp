resource "google_service_account" "gke_node" {
  count = (var.create_node_service_account ? 1 : 0)

  account_id   = "${local.cluster_name}-node-sa"
  display_name = "GKE Node Service Account for ${local.cluster_name}"
  project      = var.project_id
}

locals {
  gke_node_service_account_email = (var.create_node_service_account ?
    google_service_account.gke_node[0].email :
    var.gke_node_service_account_email)
}

resource "google_compute_subnetwork_iam_member" "gke_node_network_user" {
  for_each = (var.subnets == null ? {} : (var.configure_network_role ? var.subnets : {}))

  subnetwork = each.value.name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${local.gke_node_service_account_email}"
  project    = var.project_id
  region     = var.region
}

# GKE nodes typically do not require explicit route table permissions granted to their service account.
# The Azure route table role assignment is omitted as it's an Azure network-specific concept
# not directly mapping to GKE node network requirements.

resource "google_container_cluster" "gke_cluster" {
  name               = local.cluster_name
  project            = var.project_id
  location           = var.region

  description        = "Converted from Azure AKS"
  initial_node_count = (local.node_pools[var.default_node_pool].enable_auto_scaling ?
                        max(1, local.node_pools[var.default_node_pool].min_count) :
                        local.node_pools[var.default_node_pool].node_count)

  min_master_version = var.kubernetes_version

  resource_labels = var.tags

  network    = var.vpc_network_name
  subnetwork = var.subnets[local.node_pools[var.default_node_pool].subnet].name

  ip_allocation_policy {
    cluster_secondary_range_name = var.subnets[local.node_pools[var.default_node_pool].subnet].secondary_ip_range_names.pods
    services_secondary_range_name = var.subnets[local.node_pools[var.default_node_pool].subnet].secondary_ip_range_names.services
  }

  enable_network_policy = var.network_policy
  networking_mode       = "VPC_NATIVE"

  private_cluster_config {
    enable_private_endpoint = var.private_cluster_enabled
    enable_private_nodes    = var.private_cluster_enabled
  }

  master_authorized_networks_config {
    dynamic "cidr_block" {
      for_each = local.api_server_authorized_ip_ranges
      content {
        cidr_block   = cidr_block.value
        display_name = "auth-ip-${cidr_block.key}"
      }
    }
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # Omit Azure Policy and Kube Dashboard (deprecated in GKE) addons

  node_config {
    service_account = local.gke_node_service_account_email
    # enable_host_encryption, enable_node_public_ip are not direct node_config parameters
  }

  enable_rbac = var.rbac.enabled

  dynamic "authenticator_groups_config" {
    for_each = (var.rbac.enabled && var.rbac.ad_integration ? [1] : [])
    content {
      security_group = var.rbac_admin_google_group_email # Assuming a single Google Group for GKE Auth
    }
  }

  node_pool {
    name                         = var.default_node_pool
    initial_node_count           = local.node_pools[var.default_node_pool].node_count
    version                      = local.node_pools[var.default_node_pool].orchestrator_version

    node_config {
      machine_type      = local.node_pools[var.default_node_pool].vm_size
      disk_size_gb      = local.node_pools[var.default_node_pool].os_disk_size_gb
      disk_type         = local.node_pools[var.default_node_pool].os_disk_type
      image_type        = "COS_CONTAINERD" # Map Azure os_type if needed, COS_CONTAINERD is common
      service_account   = local.gke_node_service_account_email
      max_pods_per_node = local.node_pools[var.default_node_pool].max_pods

      labels = local.node_pools[var.default_node_pool].node_labels
      tags   = local.node_pools[var.default_node_pool].tags

      subnetwork        = var.subnets[local.node_pools[var.default_node_pool].subnet].name

       dynamic "taint" {
         for_each = local.node_pools[var.default_node_pool].node_taints
         content {
           key    = taint.value.key
           value  = taint.value.value
           effect = taint.value.effect
         }
       }
    }

    autoscaling {
      enabled        = local.node_pools[var.default_node_pool].enable_auto_scaling
      min_node_count = (local.node_pools[var.default_node_pool].enable_auto_scaling ? local.node_pools[var.default_node_pool].min_count : null)
      max_node_count = (local.node_pools[var.default_node_pool].enable_auto_scaling ? local.node_pools[var.default_node_pool].max_count : null)
    }

    upgrade_settings {
      max_surge = local.node_pools[var.default_node_pool].max_surge
    }

    locations = local.node_pools[var.default_node_pool].availability_zones
  }

  # Omit Windows profile (GKE Enterprise feature)
}

resource "google_container_cluster_iam_member" "rbac_admin" {
  for_each = (var.rbac.enabled && var.rbac.ad_integration ? var.rbac_admin_principals : {})

  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.gke_cluster.name
  # Grant roles/container.clusterAdmin or roles/container.developer/viewer based on need
  role     = "roles/container.clusterAdmin"
  member   = "group:${each.value}" # Assuming principals are Google Group emails
}


resource "google_container_node_pool" "additional" {
  for_each = local.additional_node_pools

  project              = var.project_id
  location             = var.region
  cluster              = google_container_cluster.gke_cluster.name

  name                 = each.key
  initial_node_count   = each.value.node_count
  version              = each.value.orchestrator_version

  node_config {
    machine_type      = each.value.vm_size
    disk_size_gb      = each.value.os_disk_size_gb
    disk_type         = each.value.os_disk_type
    image_type        = each.value.os_type # Map Azure os_type (Linux, Windows) to GKE image_type
    service_account   = local.gke_node_service_account_email
    max_pods_per_node = each.value.max_pods

    labels = each.value.node_labels
    tags   = each.value.tags

    subnetwork        = var.subnets[each.value.subnet].name

    dynamic "taint" {
      for_each = each.value.node_taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    spot = (each.value.priority == "Spot")
    # Spot config details like eviction_policy, spot_max_price can be mapped here if needed
    # proximity_placement_group_id has no direct GKE node pool parameter
  }

  autoscaling {
    enabled        = each.value.enable_auto_scaling
    min_node_count = (each.value.enable_auto_scaling ? each.value.min_count : null)
    max_node_count = (each.value.enable_auto_scaling ? each.value.max_count : null)
  }

  upgrade_settings {
    max_surge = each.value.max_surge
  }

  locations = each.value.availability_zones

  # mode (System/User) is not applicable in GKE standard node pools
}

# Equivalent to azurerm_role_assignment.acr_pull
# Grant roles/artifactregistry.reader and roles/storage.objectViewer to the node service account
# This grants pull access from Artifact Registry and Container Registry within the project.
resource "google_project_iam_member" "gke_node_registry_reader_ar" {
  count = length(var.acr_pull_access) > 0 ? 1 : 0

  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${local.gke_node_service_account_email}"
}

resource "google_project_iam_member" "gke_node_registry_reader_gcr" {
  count = length(var.acr_pull_access) > 0 ? 1 : 0

  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${local.gke_node_service_account_email}"
}
```