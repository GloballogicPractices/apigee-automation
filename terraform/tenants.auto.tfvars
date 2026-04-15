gcp_project_id = "apigee-490614"
apigee_org_id  = "apigee-490614"
gcp_region     = "us-central1"

# Premium Tenants (Environment-per-Tenant)
model_a_tenants = {
  "alpha-corp" = {
    hostname       = "alpha.api.company.com"
    env_tier       = "COMPREHENSIVE"
    dev_email      = "admin@alphacorp.com"
    app_name       = "alpha_core_app"
    backend_url    = "api.alphainternal.net"
  }
}

# Standard Tenants (Shared Pool)
model_b_tenants = {
  "startup-inc" = { 
    hostname     = "startup.api.company.com" # NEW
    email        = "admin@startup.com", 
    first_name   = "Startup", 
    last_name    = "Inc", 
    app_name     = "startup_prod_app" 
  },
  "beta-corp" = { 
    hostname     = "beta.api.company.com"   # NEW
    email        = "dev@betacorp.com", 
    first_name   = "Beta", 
    last_name    = "Corp", 
    app_name     = "beta_api_client" 
  }
}