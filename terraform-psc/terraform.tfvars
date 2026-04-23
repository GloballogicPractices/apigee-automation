gcp_project_id = "apigee-490614"
gcp_region     = "us-central1"
base_domain    = "company.com"

model_b_tenants = {
  "startup-inc" = {
    email      = "admin@startup-inc.com"
    first_name = "Startup"
    last_name  = "Admin"
    app_name   = "startup-app"
    hostname   = "startup.api.company.com"
  },
  "beta-corp" = {
    email      = "dev@beta-corp.com"
    first_name = "Beta"
    last_name  = "User"
    app_name   = "beta-test-app"
    hostname   = "beta.api.company.com"
  }
}

model_a_tenants = {
  "alpha-corp" = {
    dev_email   = "it-admin@alpha-corp.com"
    app_name    = "alpha-enterprise-app"
    hostname    = "alpha.api.company.com"
    backend_url = "alpha-internal-svc.local"
  }
}