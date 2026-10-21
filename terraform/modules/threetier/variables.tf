variable "name_prefix" {
  type = string
}
variable "region" {
  type = string
}
variable "environment" {
  type = string
}
variable "machine_type" {
  type = string
}
variable "min_replicas" {
  type = number
}
variable "max_replicas" {
  type = number
}
variable "db_tier" {
  type = string
}
variable "db_user" {
  type = string
}
variable "db_password" {
  type      = string
  sensitive = true
}
