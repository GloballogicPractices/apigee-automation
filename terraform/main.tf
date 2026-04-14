# ==============================================================================
# APIGEE ORGANIZATION (The Core Foundation)
# ==============================================================================

# 1. Enable the Compute Engine API
resource "google_project_service" "compute_api" {
  project            = var.gcp_project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# 2. Enable the Service Networking API
resource "google_project_service" "servicenetworking_api" {
  project            = var.gcp_project_id
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

# 3. Allocate a /22 IP Range for the Apigee instances
resource "google_compute_global_address" "apigee_peering_range" {
  name          = "apigee-peering-range"
  project       = var.gcp_project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 22
  network       = "projects/${var.gcp_project_id}/global/networks/default" # The network from your error

  depends_on = [google_project_service.compute_api]
}

# 4. Create the private connection bridge
resource "google_service_networking_connection" "apigee_vpc_connection" {
  network                 = "projects/${var.gcp_project_id}/global/networks/default"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.apigee_peering_range.name]

  depends_on = [google_project_service.servicenetworking_api]
}

resource "google_apigee_organization" "apigee_org" {
  project_id         = var.gcp_project_id
  analytics_region   = var.gcp_region
  authorized_network = "default" # Change this to your peered VPC network name

  # Force Terraform to enable the API before trying to create the Org
  # depends_on = [google_project_service.apigee_api] 
}

resource "google_apigee_instance" "apigee_instance" {
  name     = "runtime-instance-main"
  location = var.gcp_region
  org_id   = google_apigee_organization.apigee_org.id
  
  # For evaluation/testing, /22 is the standard required CIDR block size
  peering_cidr_range = "SLASH_22" 
}

# ==============================================================================
# MODEL B: SHARED POOL INFRASTRUCTURE (Provisioned Once)
# ==============================================================================

# 1. Create the Shared Environment
resource "google_apigee_environment" "shared_pool_env" {
  org_id          = google_apigee_organization.apigee_org.id
  name            = "env-standard-pool"
  description     = "Shared environment for Model B tenants"
  deployment_type = "PROXY"
  api_proxy_type  = "PROGRAMMABLE"
  # type            = "BASE" 
}

# 2. Create the Shared Environment Group (Routing)
resource "google_apigee_envgroup" "shared_pool_group" {
  org_id    = google_apigee_organization.apigee_org.id
  name      = "envgroup-standard-pool"
  hostnames = ["shared.api.company.com"]
}

# 3. Attach Shared Env to Shared Group
resource "google_apigee_envgroup_attachment" "shared_pool_attach" {
  envgroup_id = google_apigee_envgroup.shared_pool_group.id
  environment = google_apigee_environment.shared_pool_env.name
}

# 4. Create the Shared API Product
resource "google_apigee_api_product" "shared_product" {
  org_id        = google_apigee_organization.apigee_org.id
  name          = "product-shared-standard"
  display_name  = "Standard Shared Tier"
  environments  = [google_apigee_environment.shared_pool_env.name]
  approval_type = "auto"
  depends_on = [google_apigee_instance_attachment.shared_pool_instance_attach]
}

# 5. Loop & Create Model B Developers
resource "google_apigee_developer" "model_b_devs" {
  for_each   = var.model_b_tenants
  org_id     = google_apigee_organization.apigee_org.id
  email      = each.value.email
  first_name = each.value.first_name
  last_name  = each.value.last_name
  user_name  = each.key
}

# 6. Loop & Create Model B Apps (Injects Custom Attributes for Logic/Billing)
resource "google_apigee_developer_app" "model_b_apps" {
  for_each        = var.model_b_tenants
  org_id          = google_apigee_organization.apigee_org.id
  developer_email = google_apigee_developer.model_b_devs[each.key].email
  name            = each.value.app_name
  api_products    = [google_apigee_api_product.shared_product.name]
# Required by Terraform. You can use a dummy URL if not utilizing OAuth2 callbacks.
  callback_url    = "https://${each.key}.company.com/oauth/callback"

  # Correct attributes block syntax
  attributes {
    name  = "tenant_id"
    value = each.key
  }

  attributes {
    name  = "isolation_model"
    value = "B"
  }
}

resource "google_apigee_instance_attachment" "shared_pool_instance_attach" {
  instance_id = google_apigee_instance.apigee_instance.id
  environment = google_apigee_environment.shared_pool_env.name
}


# ==============================================================================
# MODEL A: DEDICATED INFRASTRUCTURE (Provisioned per Tenant)
# ==============================================================================

# 1. Loop & Create Dedicated Environments
resource "google_apigee_environment" "model_a_envs" {
  for_each        = var.model_a_tenants
  org_id          = google_apigee_organization.apigee_org.id
  name            = "env-premium-${each.key}"
  description     = "Isolated Model A environment for ${each.key}"
  deployment_type = "PROXY"
  api_proxy_type  = "PROGRAMMABLE"
  # type            = each.value.env_tier
}

# 2. Loop & Create Dedicated Environment Groups (Custom DNS per tenant)
resource "google_apigee_envgroup" "model_a_groups" {
  for_each  = var.model_a_tenants
  org_id    = google_apigee_organization.apigee_org.id
  name      = "envgroup-${each.key}"
  hostnames = [each.value.hostname]
}

# 3. Attach Dedicated Envs to their Groups
resource "google_apigee_envgroup_attachment" "model_a_attachments" {
  for_each    = var.model_a_tenants
  envgroup_id = google_apigee_envgroup.model_a_groups[each.key].id
  environment = google_apigee_environment.model_a_envs[each.key].name
}

# 4. Create Dedicated Target Servers for strict backend routing
resource "google_apigee_target_server" "model_a_targets" {
  for_each = var.model_a_tenants
  name     = "primary-backend"
  env_id   = google_apigee_environment.model_a_envs[each.key].id
  host     = each.value.backend_url
  port     = 443
  s_sl_info { enabled = true }
}

# 5. Create Dedicated API Products
resource "google_apigee_api_product" "model_a_products" {
  for_each      = var.model_a_tenants
  org_id        = var.apigee_org_id
  name          = "product-${each.key}"
  display_name  = "Premium Tier - ${each.key}"
  environments  = [google_apigee_environment.model_a_envs[each.key].name]
  approval_type = "auto"
  depends_on = [google_apigee_instance_attachment.model_a_instance_attach]
}

# 6. Create Model A Developers
resource "google_apigee_developer" "model_a_devs" {
  for_each   = var.model_a_tenants
  org_id     = var.apigee_org_id
  email      = each.value.dev_email
  first_name = "Admin"
  last_name  = each.key
  user_name  = each.key
}

# 7. Create Model A Apps (With attributes for billing parity)
resource "google_apigee_developer_app" "model_a_apps" {
  for_each        = var.model_a_tenants
  org_id          = var.apigee_org_id
  developer_email = google_apigee_developer.model_a_devs[each.key].email
  name            = each.value.app_name
  api_products    = [google_apigee_api_product.model_a_products[each.key].name]
# Required by Terraform.
  callback_url    = "https://${each.key}.company.com/oauth/callback"

  # Correct attributes block syntax
  attributes {
    name  = "tenant_id"
    value = each.key
  }

  attributes {
    name  = "isolation_model"
    value = "A"
  }
}

resource "google_apigee_instance_attachment" "model_a_instance_attach" {
  for_each    = var.model_a_tenants
  instance_id = google_apigee_instance.apigee_instance.id
  environment = google_apigee_environment.model_a_envs[each.key].name
}