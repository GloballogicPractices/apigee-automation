variable "gcp_project_id" {
  type        = string
  description = "The Google Cloud Project ID where Apigee will be deployed."
}

variable "gcp_region" {
  type        = string
  description = "The GCP region for the Apigee instance and computing resources."
  default     = "us-central1"
}

variable "base_domain" {
  type        = string
  description = "The root domain used for all vanity URLs (e.g., company.com)."
}

variable "model_b_tenants" {
  type = map(object({
    email      = string
    first_name = string
    last_name  = string
    app_name   = string
    hostname   = string
  }))
  description = "A map of tenants for the Model B Shared Pool."
}

variable "model_a_tenants" {
  type = map(object({
    dev_email   = string
    app_name    = string
    hostname    = string
    backend_url = string
  }))
  description = "A map of premium tenants for the Model A Dedicated Tier."
}