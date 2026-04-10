

# 1. Create a Dedicated Environment per Tenant
resource "google_apigee_environment" "tenant_env" {
  for_each         = var.model_a_tenants
  org_id           = var.apigee_org_id
  name             = "env-premium-${each.key}"
  description      = "Isolated Model A environment for ${each.key}"
  deployment_type  = "PROXY"
  api_proxy_type   = "PROGRAMMABLE"
  type             = each.value.env_tier # Base, Intermediate, or Comprehensive
}

# 2. Create a Dedicated Environment Group (Traffic Routing)
resource "google_apigee_envgroup" "tenant_envgroup" {
  for_each  = var.model_a_tenants
  org_id    = var.apigee_org_id
  name      = "envgroup-${each.key}"
  hostnames = [each.value.hostname]
}

# 3. Attach the Environment to the Environment Group
resource "google_apigee_envgroup_attachment" "tenant_attachment" {
  for_each    = var.model_a_tenants
  envgroup_id = google_apigee_envgroup.tenant_envgroup[each.key].id
  environment = google_apigee_environment.tenant_env[each.key].name
}

# 4. Create an Isolated Target Server (Hard Isolation for Backends)
# This allows your proxy code to just use <TargetServer>primary-backend</TargetServer>
# while routing dynamically per tenant environment.
resource "google_apigee_target_server" "tenant_backend" {
  for_each = var.model_a_tenants
  name     = "primary-backend"
  env_id   = google_apigee_environment.tenant_env[each.key].id
  host     = each.value.backend_url
  port     = 443
  
  s_sl_info {
    enabled = true
  }
}

# 5. Create a Dedicated API Product Scoped ONLY to this Environment
resource "google_apigee_api_product" "tenant_product" {
  for_each     = var.model_a_tenants
  org_id       = var.apigee_org_id
  name         = "product-${each.key}"
  display_name = "Premium Tier - ${each.key}"
  environments = [google_apigee_environment.tenant_env[each.key].name]
  approval_type= "auto"
}

# 6. Create Developer
resource "google_apigee_developer" "tenant_dev" {
  for_each   = var.model_a_tenants
  org_id     = var.apigee_org_id
  email      = each.value.dev_email
  first_name = "Admin"
  last_name  = each.key
  user_name  = each.key
}

# 7. Create Developer App & Generate Credentials
resource "google_apigee_developer_app" "tenant_app" {
  for_each        = var.model_a_tenants
  org_id          = var.apigee_org_id
  developer_email = google_apigee_developer.tenant_dev[each.key].email
  name            = each.value.app_name
  api_products    = [google_apigee_api_product.tenant_product[each.key].name]

  # Tag for BigQuery Analytics (Maintains parity with the Model B billing engine)
  attributes = {
    tenant_id       = each.key
    isolation_model = "A"
  }
}

# Output the API Keys to securely pass back to the tenants
output "model_a_api_keys" {
  value = {
    for k, v in google_apigee_developer_app.tenant_app : k => v.credentials.consumer_key
  }
  sensitive = true
}