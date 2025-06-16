output "id" {
  description = "kubernetes managed cluster id"
  value       = google_container_cluster.gke.id
}

output "name" {
  description = "kubernetes managed cluster name"
  value       = google_container_cluster.gke.name
}

output "endpoint" {
  description = "kubernetes master endpoint"
  value       = google_container_cluster.gke.endpoint
}

output "cluster_ca_certificate" {
  description = "kubernetes cluster ca certificate (from master_auth if configured)"
  value       = google_container_cluster.gke.master_auth[0].cluster_ca_certificate
}

output "master_username" {
  description = "kubernetes master username (from master_auth if basic auth configured)"
  value       = google_container_cluster.gke.master_auth[0].username
}

output "master_password" {
  description = "kubernetes master password (from master_auth if basic auth configured)"
  sensitive   = true
  value       = google_container_cluster.gke.master_auth[0].password
}

output "master_client_certificate" {
  description = "kubernetes master client certificate (from master_auth if client cert auth configured)"
  value       = google_container_cluster.gke.master_auth[0].client_certificate
}

output "master_client_key" {
  description = "kubernetes master client key (from master_auth if client cert auth configured)"
  sensitive   = true
  value       = google_container_cluster.gke.master_auth[0].client_key
}

output "node_service_account" {
  description = "The service account utilized by node VMs"
  value       = google_container_cluster.gke.node_config[0].service_account
}