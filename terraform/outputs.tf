output "load_balancer_ip" {
  value = module.threetier.load_balancer_ip
}
output "application_url" {
  value = "http://${module.threetier.load_balancer_ip}"
}
output "sql_connection_name" {
  value = module.threetier.sql_connection_name
}
