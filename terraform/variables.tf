variable "project_id" {
  type    = string
  default = "your-gcp-project-id"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "project_name" {
  type    = string
  default = "ahmad-3tier"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric/hyphens, 2-31 chars."
  }
}

variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "machine_type" {
  type    = string
  default = "e2-small"
}

variable "min_replicas" {
  type    = number
  default = 2
}

variable "max_replicas" {
  type    = number
  default = 4
}

variable "db_tier" {
  type    = string
  default = "db-f1-micro"
}

variable "db_user" {
  type    = string
  default = "appuser"
}

variable "db_password" {
  type      = string
  sensitive = true
}
