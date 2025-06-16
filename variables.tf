variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "The GCP region for the cluster."
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
}

variable "labels" {
  description = "Labels to be applied to the cluster."
  type        = map(string)
  default     = {}
}

variable "description" {
  description = "Description of the GKE cluster."
  type        = string
  default     = null
}

variable "release_channel" {
  description = "The release channel for the cluster. Available options are 'RAPID', 'REGULAR', 'STABLE'."
  type        = string
  default     = "REGULAR"
}

variable "initial_node_count" {
  description = "The number of nodes to create in the default node pool. This variable is often replaced by defining the default pool explicitly in `node_pools`."
  type        = number
  default     = 1 # Matches AKS default node_count
}

variable "network" {
  description = "The name or self_link of the Google Compute Engine network to which the cluster is connected. If left empty, the default network is used."
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "The name or self_link of the Google Compute Engine subnetwork to which the cluster is connected. If left empty, a subnetwork in the default network is used."
  type        = string
  default     = "default"
}

variable "ip_allocation_policy" {
  description = "Configuration for cluster networking using VPC-native IP allocation. Define secondary ranges for pods and services."
  type = object({
    cluster_secondary_range_name  = string # Name of the secondary range for pods
    services_secondary_range_name = string # Name of the secondary range for services
  })
  default = null # Defaults to routes-based networking or auto-created secondary ranges if network/subnetwork are defaulted
}

variable "private_cluster_config" {
  description = "Configuration for private cluster setup."
  type = object({
    enable_private_nodes    = bool   # Whether the nodes are configured without external IP addresses.
    enable_private_endpoint = bool   # Whether the master's internal IP address is used as the API server endpoint.
    master_ipv4_cidr_block  = string # The CIDR range of the internal IP address associated with the master endpoint.
  })
  default = null # Defaults to public cluster
}

variable "enable_network_policy" {
  description = "Whether network policy is enabled for the cluster. Default network policy provider is Calico."
  type        = bool
  default     = false # Corresponds to AKS default null/disabled state
}

variable "master_authorized_networks_config" {
  description = "Configuration for controlling access to the master's API endpoint. Map keys are descriptive names, values are CIDR blocks."
  type        = map(string)
  default     = {} # Defaults to allowing all IP addresses
}

variable "logging_service" {
  description = "The logging service used for the cluster. e.g., 'logging.googleapis.com/kubernetes', 'none'."
  type        = string
  default     = "logging.googleapis.com/kubernetes" # Equivalent to enabling Log Analytics integration
}

variable "monitoring_service" {
  description = "The monitoring service used for the cluster. e.g., 'monitoring.googleapis.com/kubernetes', 'none'."
  type        = string
  default     = "monitoring.googleapis.com/kubernetes" # Equivalent to enabling Monitoring
}

variable "service_account" {
  description = "The service account to be used by the node pools. If left empty, the Compute Engine default service account is used."
  type        = string
  default     = null
}

variable "oauth_scopes" {
  description = "List of scopes to be made available to the nodes."
  type        = list(string)
  default = [
    "cloud-platform" # Common default scope for GKE nodes
  ]
}

variable "node_pools" {
  description = "Map of node pool definitions. Keys are node pool names."
  type        = any # Use 'any' for flexibility similar to Azure example
  default     = { default = {} } # Defines a 'default' node pool
}

variable "node_pool_defaults" {
  description = "Default values for node pool properties."
  type = object({
    machine_type       = string # Corresponds to vm_size
    disk_size_gb       = number # Corresponds to os_disk_size_gb
    disk_type          = string # Corresponds to os_disk_type
    node_count         = number # Corresponds to node_count (when autoscaling is off)
    autoscaling = object({
      min_node_count = number # Corresponds to min_count
      max_node_count = number # Corresponds to max_count
    })
    locations          = list(string) # Corresponds to availability_zones
    node_labels        = map(string)  # Corresponds to node_labels
    taints             = list(string) # Corresponds to node_taints
    max_pods_per_node  = number       # Corresponds to max_pods
    image_type         = string       # Corresponds to os_type (Linux, COS, Ubuntu, Windows, etc.)
    preemptible        = bool         # Corresponds to priority=Spot/eviction_policy
    disk_auto_delete   = bool
    local_ssd_count    = number
    tags               = list(string) # Corresponds to node pool tags
    upgrade_settings = object({
      max_surge       = number # Corresponds to max_surge
      max_unavailable = number
    })
    service_account    = string # Override cluster service account
    oauth_scopes       = list(string) # Override cluster oauth scopes
    spot               = bool # Alias for preemptible
  })
  default = {
    machine_type       = "e2-medium" # Corresponds to "Standard_B2s" equivalent
    disk_size_gb       = 100
    disk_type          = "pd-standard" # Corresponds to "Managed" disk type equivalent
    node_count         = 1
    autoscaling = {
      min_node_count = null
      max_node_count = null
    }
    locations          = [] # Inherit from cluster regions/zones
    node_labels        = {}
    taints             = []
    max_pods_per_node  = 110 # Default max pods in GKE VPC-native
    image_type         = "COS_CONTAINERD" # Common GKE OS
    preemptible        = false
    disk_auto_delete   = true
    local_ssd_count    = 0
    tags               = []
    upgrade_settings = {
      max_surge       = 1
      max_unavailable = 0
    }
    service_account    = null # Inherit from cluster default
    oauth_scopes       = null # Inherit from cluster default
    spot               = null # Alias for preemptible
  }
}

variable "default_node_pool_name" {
  description = "The name of the default node pool defined in `node_pools`. This pool is created initially with the cluster."
  type        = string
  default     = "default"
}

# Variables from AKS code that have no direct GCP equivalent or are handled differently:
# - names: Generic naming, handled by resource names and labels.
# - dns_prefix: GKE handles DNS internally.
# - node_resource_group: GCP resources are project/region/zone scoped.
# - identity_type, user_assigned_identity, user_assigned_identity_name: Replaced by `service_account`.
# - sku_tier: GKE Standard is the equivalent tier for manual node pools. Autopilot is a different model.
# - network_plugin: GKE CNI is less configurable at this level, usually Calico/Dataplane V2.
# - outbound_type: Egress handled by VPC/NAT.
# - network_profile_options: Docker bridge CIDR is internal; Service/Pod CIDRs linked to secondary ranges.
# - enable_host_encryption: Handled by disk encryption settings, usually default.
# - enable_node_public_ip: Nodes typically don't get public IPs by default.
# - only_critical_addons_enabled: AKS specific.
# - type (node pool): GKE uses Instance Groups.
# - subnet (node pool): Node pools inherit cluster subnet.
# - mode (node pool): AKS System/User pools.
# - eviction_policy (node pool): Replaced by `preemptible`.
# - proximity_placement_group_id: GCP has Compact Placement Policies (advanced).
# - spot_max_price (node pool): GCP preemptible VMs have fixed price.
# - configure_network_role: GCP service account roles are managed differently.
# - windows_profile: Handled via `image_type` and potentially instance metadata for credentials/startup scripts.
# - rbac, rbac_admin_object_ids: K8s RBAC default enabled; GCP IAM/Google Groups integration handled differently.
# - enable_kube_dashboard: Not recommended/enabled by default in modern GKE.
# - enable_azure_policy: GCP equivalent is Policy Controller (Gatekeeper). Could add a variable if needed.
# - acr_pull_access: Replaced by node service account permissions (e.g., storage.viewer).
# - log_analytics_workspace_id: Replaced by `logging_service` and `monitoring_service`.