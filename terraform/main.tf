locals {
  name_prefix = var.project_name
}

module "threetier" {
  source       = "./modules/threetier"
  name_prefix  = local.name_prefix
  region       = var.region
  environment  = var.environment
  machine_type = var.machine_type
  min_replicas = var.min_replicas
  max_replicas = var.max_replicas
  db_tier      = var.db_tier
  db_user      = var.db_user
  db_password  = var.db_password
}
