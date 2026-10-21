locals {
  labels = {
    project     = var.name_prefix
    environment = var.environment
    managed_by  = "terraform"
    owner       = "muhammad-ahmad"
  }
}

resource "random_id" "suffix" {
  byte_length = 3
}

############################
# Network + NAT + firewall
############################
resource "google_compute_network" "this" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  name                     = "${var.name_prefix}-subnet"
  ip_cidr_range            = "10.0.0.0/16"
  region                   = var.region
  network                  = google_compute_network.this.id
  private_ip_google_access = true
}

resource "google_compute_router" "this" {
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.name_prefix}-allow-hc"
  network = google_compute_network.this.id
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web"]
}

############################
# Web tier (private MIG)
############################
resource "google_compute_instance_template" "web" {
  name_prefix  = "${var.name_prefix}-tpl-"
  machine_type = var.machine_type
  tags         = ["web"]
  labels       = local.labels

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.this.id
    # no access_config: private instances egress via Cloud NAT
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update && apt-get install -y nginx
    echo "<h1>GCP 3-Tier web node - deployed by Muhammad Ahmad</h1>" > /var/www/html/index.html
    systemctl enable nginx && systemctl restart nginx
  EOT

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_health_check" "web" {
  name = "${var.name_prefix}-hc"
  http_health_check {
    port = 80
  }
}

resource "google_compute_region_instance_group_manager" "web" {
  name               = "${var.name_prefix}-mig"
  region             = var.region
  base_instance_name = "${var.name_prefix}-web"

  version {
    instance_template = google_compute_instance_template.web.id
  }
  named_port {
    name = "http"
    port = 80
  }
  auto_healing_policies {
    health_check      = google_compute_health_check.web.id
    initial_delay_sec = 120
  }
}

resource "google_compute_region_autoscaler" "web" {
  name   = "${var.name_prefix}-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.web.id
  autoscaling_policy {
    max_replicas    = var.max_replicas
    min_replicas    = var.min_replicas
    cooldown_period = 60
    cpu_utilization {
      target = 0.6
    }
  }
}

############################
# Global HTTP LB
############################
resource "google_compute_backend_service" "web" {
  name                  = "${var.name_prefix}-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.web.id]
  backend {
    group = google_compute_region_instance_group_manager.web.instance_group
  }
}

resource "google_compute_url_map" "web" {
  name            = "${var.name_prefix}-urlmap"
  default_service = google_compute_backend_service.web.id
}

resource "google_compute_target_http_proxy" "web" {
  name    = "${var.name_prefix}-proxy"
  url_map = google_compute_url_map.web.id
}

resource "google_compute_global_address" "web" {
  name = "${var.name_prefix}-lb-ip"
}

resource "google_compute_global_forwarding_rule" "web" {
  name                  = "${var.name_prefix}-forwarding-rule"
  target                = google_compute_target_http_proxy.web.id
  port_range            = "80"
  ip_address            = google_compute_global_address.web.address
  load_balancing_scheme = "EXTERNAL"
}

############################
# Data tier
############################
resource "google_sql_database_instance" "this" {
  name             = "${var.name_prefix}-sql-${random_id.suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.region
  settings {
    tier = var.db_tier
    backup_configuration {
      enabled = true
    }
    ip_configuration {
      ssl_mode = "ENCRYPTED_ONLY"
    }
  }
  deletion_protection = false
}

resource "google_sql_database" "this" {
  name     = "appdb"
  instance = google_sql_database_instance.this.name
}

resource "google_sql_user" "this" {
  name     = var.db_user
  instance = google_sql_database_instance.this.name
  password = var.db_password
}
