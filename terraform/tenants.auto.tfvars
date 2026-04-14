gcp_project_id = "your-gcp-project-id"
apigee_org_id  = "your-gcp-project-id"
gcp_region     = "us-central1"

# Premium Tenants (Environment-per-Tenant)
model_a_tenants = {
  "alpha_corp" = {
    hostname       = "alpha.api.company.com"
    env_tier       = "COMPREHENSIVE"
    dev_email      = "admin@alphacorp.com"
    app_name       = "alpha_core_app"
    backend_url    = "api.alphainternal.net"
  },
  "omega_finance" = {
    hostname       = "api.omegafinance.com"
    env_tier       = "INTERMEDIATE"
    dev_email      = "tech@omegafinance.com"
    app_name       = "omega_trading_app"
    backend_url    = "backend.omega.local"
  }
}

# Standard Tenants (Shared Pool)
model_b_tenants = {
  "startup_inc" = { 
    email        = "admin@startup.com", 
    first_name   = "Startup", 
    last_name    = "Inc", 
    app_name     = "startup_prod_app" 
  },
  "beta_corp" = { 
    email        = "dev@betacorp.com", 
    first_name   = "Beta", 
    last_name    = "Corp", 
    app_name     = "beta_api_client" 
  }
}