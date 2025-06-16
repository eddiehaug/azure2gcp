locals {
  # Derive cluster name based on naming conventions or explicit variable
  cluster_name = (var.cluster_name != null ? var.cluster_name :
  "${var.names.resource_type}-${var.names.product_name}-${var.names.environment}-${var.names.location}") # Note: resource_type/location in GCP context might map to resource type/region

  # Merge default node pool settings with individual node pool configurations
  node_pools = zipmap(keys(var.node_pools), [for node_pool in values(var.node_pools) : merge(var.node_pool_defaults, node_pool)])

  # Identify node pools other than the default one
  additional_node_pools = { for k, v in local.node_pools : k => v if k != var.default_node_pool }

  # Check if any node pool is configured for Windows OS
  windows_nodes = (length([for v in values(local.node_pools) : v if lower(v.os_type) == "windows"]) > 0 ? true : false)

  # Configuration for restricting API server access by IP range
  # GCP uses 'master_authorized_networks_config'
  master_authorized_networks_config = var.master_authorized_networks_config

  # Determine the service account email for node pools.
  # This often defaults to the Compute Engine default service account (@developer.gserviceaccount.com)
  # or can be explicitly set via a variable.
  # Assuming var.node_service_account is the email string or null for default.
  node_service_account_email = var.node_service_account

  # --- Validation Locals (adapted for GCP) ---
  # Basic check if cluster_name or naming variables are provided
  validate_cluster_name = ((var.cluster_name == null && var.names == null) ?
  file("ERROR: cluster_name or names variable must be specified.") : null)

  # Basic check for invalid node pool attributes based on default definition
  # Note: This is a generic validation pattern. The set of valid attributes
  # depends entirely on the structure defined in var.node_pool_defaults.
  invalid_node_pool_attributes = join(",", flatten([for np in values(local.node_pools) : [for k, v in np : k if !(contains(keys(var.node_pool_defaults), k))]]))
  validate_node_pool_attributes = (length(local.invalid_node_pool_attributes) > 0 ?
  file("ERROR: invalid node pool attribute:  ${local.invalid_node_pool_attributes}") : null)

  # Remove Azure-specific locals and validations:
  # - user_assigned_identity_name, aks_identity_id (identity model differs)
  # - node_resource_group, validate_node_resource_group_length (GCP manages nodes differently)
  # - dns_prefix, validate_dns_prefix (GKE FQDN auto-generated)
  # - validate_virtual_network_support (Azure VNet specific)
  # - validate_multiple_node_pools (Azure AKS specific restriction)
  # - validate_default_node_pool (Azure AKS specific restriction)
  # - validate_critical_addons (Azure AKS specific concept)
  # - validate_network_policy (Azure AKS specific policy/plugin interaction)
  # - validate_windows_config (Specific check removed; GKE image validation is done by provider/API)
}