variable "gcp_project_id" {
  description = "The ID of the Google Cloud Project"
  type        = string
}

variable "gcp_region" {
  description = "The region for standard resources"
  type        = string
  default     = "us-central1"
}

variable "apigee_org_id" {
  description = "The Apigee Organization ID (usually matches the Project ID)"
  type        = string
}

variable "model_a_tenants" {
  description = "Tenants requiring High Isolation (Dedicated Environments)"
  type = map(object({
    hostname    = string
    env_tier    = string
    dev_email   = string
    app_name    = string
    backend_url = string
  }))
}

variable "model_b_tenants" {
  description = "Tenants using Logical Isolation (Shared Environment)"
  type = map(object({
    email      = string
    first_name = string
    last_name  = string
    app_name   = string
  }))
}