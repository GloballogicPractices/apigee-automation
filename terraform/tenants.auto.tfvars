gcp_project_id = "apigee-490614"
apigee_org_id  = "apigee-490614"
gcp_region     = "us-central1"

# Premium Tenants (Environment-per-Tenant)
model_a_tenants = {
  "alpha_corp" = {
    hostname       = "alpha.api.company.com"
    env_tier       = "COMPREHENSIVE"
    dev_email      = "admin@alphacorp.com"
    app_name       = "alpha-core-app"
    backend_url    = "api.alphainternal.net"
  },
  "omega_finance" = {
    hostname       = "api.omegafinance.com"
    env_tier       = "INTERMEDIATE"
    dev_email      = "tech@omegafinance.com"
    app_name       = "omeg-_trading-app"
    backend_url    = "backend.omega.local"
  }
}

# Standard Tenants (Shared Pool)
model_b_tenants = {
  "startup_inc" = { 
    email        = "admin@startup.com", 
    first_name   = "Startup", 
    last_name    = "Inc", 
    app_name     = "startup-prod-app" 
  },
  "beta_corp" = { 
    email        = "dev@betacorp.com", 
    first_name   = "Beta", 
    last_name    = "Corp", 
    app_name     = "beta-api-client" 
  }
}