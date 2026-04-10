variable "apigee_org_id" { type = string }
variable "shared_tenants" { 
  type = map(object({
    email      = string
    first_name = string
    last_name  = string
    app_name   = string
  }))
}
variable "model_a_tenants" {
  type = map(object({
    hostname    = string
    env_tier    = string
    dev_email   = string
    app_name    = string
    backend_url = string
  }))
}