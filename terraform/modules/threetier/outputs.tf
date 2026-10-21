output "load_balancer_ip" {
  value = google_compute_global_address.web.address
}
output "sql_connection_name" {
  value = google_sql_database_instance.this.connection_name
}
