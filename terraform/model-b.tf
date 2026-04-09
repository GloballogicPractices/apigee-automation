variable "apigee_org_id" { type = string }
variable "shared_tenants" { 
  type = map(object({
    email      = string
    first_name = string
    last_name  = string
    app_name   = string
  }))
}

# 1. Create a Shared API Product (Applies to all Model B tenants)
resource "google_apigee_api_product" "shared_tier_product" {
  org_id       = var.apigee_org_id
  name         = "standard-shared-product"
  display_name = "Standard Shared Tier"
  environments = ["env-standard_pool"] # Links to the shared environment
  approval_type= "auto"
}

# 2. Loop through and create a Developer for each tenant
resource "google_apigee_developer" "shared_tenant_devs" {
  for_each       = var.shared_tenants
  org_id         = var.apigee_org_id
  email          = each.value.email
  first_name     = each.value.first_name
  last_name      = each.value.last_name
  user_name      = each.key

  # Optional: Tag the developer entity directly
  attributes = {
    tenant_id       = each.key
    isolation_model = "B"
  }
}

# 3. Loop through and create an App with Custom Attributes for each tenant
resource "google_apigee_developer_app" "shared_tenant_apps" {
  for_each        = var.shared_tenants
  org_id          = var.apigee_org_id
  developer_email = google_apigee_developer.shared_tenant_devs[each.key].email
  name            = each.value.app_name
  api_products    = [google_apigee_api_product.shared_tier_product.name]

  # CRITICAL: These attributes are read by the VerifyAPIKey policy
  attributes = {
    tenant_id       = each.key
    isolation_model = "B"
  }
}

# Output the API Keys to securely pass back to the tenants
output "tenant_api_keys" {
  value = {
    for k, v in google_apigee_developer_app.shared_tenant_apps : k => v.credentials.consumer_key
  }
  sensitive = true
}