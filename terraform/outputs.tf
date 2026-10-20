output "load_balancer_ip" {
  description = "Global HTTP load balancer IP"
  value       = google_compute_global_address.web.address
}

output "application_url" {
  description = "Open once instances are healthy (LB propagation takes a few minutes)"
  value       = "http://${google_compute_global_address.web.address}"
}

output "sql_connection_name" {
  description = "Cloud SQL instance connection name"
  value       = google_sql_database_instance.this.connection_name
}
