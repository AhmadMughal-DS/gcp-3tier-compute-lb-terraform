locals {
  name = var.project_name
}

resource "random_id" "suffix" {
  byte_length = 3
}

############################
# Network + firewall
############################
resource "google_compute_network" "this" {
  name                    = "${local.name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  name          = "${local.name}-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_network.this.id
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "${local.name}-allow-hc"
  network = google_compute_network.this.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web"]
}

resource "google_compute_firewall" "allow_http" {
  name    = "${local.name}-allow-http"
  network = google_compute_network.this.id

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

############################
# Web tier: instance template + MIG + autoscaler
############################
resource "google_compute_instance_template" "web" {
  name_prefix  = "${local.name}-tpl-"
  machine_type = "e2-small"
  tags         = ["web"]

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.this.id
    access_config {} # ephemeral public IP for package install
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
  name = "${local.name}-hc"

  http_health_check {
    port = 80
  }
}

resource "google_compute_region_instance_group_manager" "web" {
  name               = "${local.name}-mig"
  region             = var.region
  base_instance_name = "${local.name}-web"

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
  name   = "${local.name}-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.web.id

  autoscaling_policy {
    max_replicas    = 4
    min_replicas    = 2
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }
}

############################
# Global HTTP load balancer
############################
resource "google_compute_backend_service" "web" {
  name                  = "${local.name}-backend"
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
  name            = "${local.name}-urlmap"
  default_service = google_compute_backend_service.web.id
}

resource "google_compute_target_http_proxy" "web" {
  name    = "${local.name}-proxy"
  url_map = google_compute_url_map.web.id
}

resource "google_compute_global_address" "web" {
  name = "${local.name}-lb-ip"
}

resource "google_compute_global_forwarding_rule" "web" {
  name                  = "${local.name}-forwarding-rule"
  target                = google_compute_target_http_proxy.web.id
  port_range            = "80"
  ip_address            = google_compute_global_address.web.address
  load_balancing_scheme = "EXTERNAL"
}

############################
# Data tier: Cloud SQL
############################
resource "google_sql_database_instance" "this" {
  name             = "${local.name}-sql-${random_id.suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-f1-micro"
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
