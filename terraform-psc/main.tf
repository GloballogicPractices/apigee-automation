# ==============================================================================
# APIGEE X - ZERO TRUST & PRIVATE SERVICE CONNECT (PSC) ARCHITECTURE
# ==============================================================================

# 1. Enable Required APIs
resource "google_project_service" "compute_api" {
  project            = var.gcp_project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "dns_api" {
  project            = var.gcp_project_id
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

# 2. Apigee Organization (PSC Mode)
# When authorized_network is omitted, the Org defaults to PSC connectivity.
resource "google_apigee_organization" "apigee_org" {
  project_id       = var.gcp_project_id
  analytics_region = var.gcp_region
  billing_type     = "EVALUATION"
}

# 3. Apigee Instance (PSC Enabled)
resource "google_apigee_instance" "apigee_instance" {
  name                 = "runtime-instance-psc"
  location             = var.gcp_region
  org_id               = google_apigee_organization.apigee_org.id
  consumer_accept_list = [var.gcp_project_id]
}

# ==============================================================================
# ZERO TRUST NETWORKING: Private Service Connect Endpoint
# ==============================================================================

resource "google_compute_address" "apigee_psc_endpoint_ip" {
  name         = "apigee-psc-endpoint-ip"
  subnetwork   = "default"
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  project      = var.gcp_project_id
  region       = var.gcp_region
}

resource "google_compute_forwarding_rule" "apigee_psc_endpoint" {
  name                  = "apigee-psc-endpoint"
  target                = google_apigee_instance.apigee_instance.service_attachment
  network               = data.google_compute_network.default_network.id
  ip_address            = google_compute_address.apigee_psc_endpoint_ip.id
  load_balancing_scheme = "" # Required to be empty for PSC Service Attachments
  project               = var.gcp_project_id
  region                = var.gcp_region
}

# ==============================================================================
# MODEL B: SHARED POOL INFRASTRUCTURE
# ==============================================================================

resource "google_apigee_environment" "shared_pool_env" {
  org_id          = google_apigee_organization.apigee_org.id
  name            = "env-standard-pool"
  deployment_type = "PROXY"
  api_proxy_type  = "PROGRAMMABLE"
}

resource "google_apigee_envgroup" "shared_pool_group" {
  org_id    = google_apigee_organization.apigee_org.id
  name      = "envgroup-standard-pool"
  hostnames = [for tenant in var.model_b_tenants : tenant.hostname]
}

resource "google_apigee_envgroup_attachment" "shared_pool_attach" {
  envgroup_id = google_apigee_envgroup.shared_pool_group.id
  environment = google_apigee_environment.shared_pool_env.name
}

resource "google_apigee_api_product" "shared_product" {
  org_id        = google_apigee_organization.apigee_org.id
  name          = "product-shared-standard"
  display_name  = "Standard Shared Tier"
  environments  = [google_apigee_environment.shared_pool_env.name]
  approval_type = "auto"
  
  quota           = "100"
  quota_interval  = "1"
  quota_time_unit = "minute"

  operation_group {
    operation_configs {
      api_source = "helloworld"
      operations {
        resource = "/"
        methods  = ["GET", "POST", "PUT", "DELETE"]
      }
    }
  }
  depends_on = [google_apigee_instance_attachment.shared_pool_instance_attach]
}

resource "google_apigee_developer" "model_b_devs" {
  for_each   = var.model_b_tenants
  org_id     = google_apigee_organization.apigee_org.id
  email      = each.value.email
  first_name = each.value.first_name
  last_name  = each.value.last_name
  user_name  = each.key
}

resource "google_apigee_developer_app" "model_b_apps" {
  for_each        = var.model_b_tenants
  org_id          = google_apigee_organization.apigee_org.id
  developer_email = google_apigee_developer.model_b_devs[each.key].email
  name            = each.value.app_name
  api_products    = [google_apigee_api_product.shared_product.name]
  callback_url    = "https://${each.key}.company.com/oauth/callback"

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
# MODEL A: DEDICATED TIER (Premium Tenants)
# ==============================================================================

resource "google_apigee_environment" "model_a_envs" {
  for_each        = var.model_a_tenants
  org_id          = google_apigee_organization.apigee_org.id
  name            = "env-premium-${each.key}"
  deployment_type = "PROXY"
  api_proxy_type  = "PROGRAMMABLE"
}

# ZERO TRUST: Admin Isolation
# Prevents tenant admins from viewing or managing other tenants' environments.
resource "google_apigee_environment_iam_member" "tenant_admin_isolation" {
  for_each = var.model_a_tenants
  org_id   = google_apigee_organization.apigee_org.id
  env_id   = google_apigee_environment.model_a_envs[each.key].name
  role     = "roles/apigee.environmentAdmin"
  member   = "group:admins@${each.key}.company.com"
}

resource "google_apigee_envgroup" "model_a_groups" {
  for_each  = var.model_a_tenants
  org_id    = google_apigee_organization.apigee_org.id
  name      = "envgroup-${each.key}"
  hostnames = [each.value.hostname]
}

resource "google_apigee_envgroup_attachment" "model_a_attachments" {
  for_each    = var.model_a_tenants
  envgroup_id = google_apigee_envgroup.model_a_groups[each.key].id
  environment = google_apigee_environment.model_a_envs[each.key].name
}

resource "google_apigee_target_server" "model_a_targets" {
  for_each = var.model_a_tenants
  name     = "primary-backend"
  env_id   = google_apigee_environment.model_a_envs[each.key].id
  host     = each.value.backend_url
  port     = 443
  s_sl_info { enabled = true }
}

resource "google_apigee_api_product" "model_a_products" {
  for_each      = var.model_a_tenants
  org_id        = google_apigee_organization.apigee_org.id
  name          = "product-${each.key}"
  display_name  = "Premium Tier - ${each.key}"
  environments  = [google_apigee_environment.model_a_envs[each.key].name]
  approval_type = "auto"

  quota           = "500"
  quota_interval  = "1"
  quota_time_unit = "minute"

  operation_group {
    operation_configs {
      api_source = "helloworld"
      operations {
        resource = "/"
        methods  = ["GET", "POST", "PUT", "DELETE"]
      }
    }
  }
  depends_on = [google_apigee_instance_attachment.model_a_instance_attach]
}

resource "google_apigee_instance_attachment" "model_a_instance_attach" {
  for_each    = var.model_a_tenants
  instance_id = google_apigee_instance.apigee_instance.id
  environment = google_apigee_environment.model_a_envs[each.key].name
}

# ==============================================================================
# ZERO TRUST EGRESS: Identity-Based Backend Calls
# ==============================================================================

resource "google_service_account" "apigee_egress_sa" {
  account_id   = "apigee-egress-identity"
  display_name = "Apigee Identity for Zero Trust Southbound"
  project      = var.gcp_project_id
}

# Allow the Apigee runtime to generate tokens using this identity
resource "google_service_account_iam_member" "apigee_sa_impersonation" {
  service_account_id = google_service_account.apigee_egress_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-apigee.iam.gserviceaccount.com"
}

data "google_project" "project" {
  project_id = var.gcp_project_id
}

# ==============================================================================
# ANALYTICS & MONITORING PIPELINE
# ==============================================================================

resource "null_resource" "apigee_analytics_setup" {
  depends_on = [google_apigee_organization.apigee_org]
  
  provisioner "local-exec" {
    command = <<EOF
      TOKEN=$(gcloud auth print-access-token)
      ORG="${var.gcp_project_id}"
      
      # Create Data Collectors
      create_dc() {
        curl -s -X POST "https://apigee.googleapis.com/v1/organizations/$ORG/datacollectors" \
          -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
          -d "{\"name\": \"$1\", \"type\": \"STRING\", \"description\": \"$2\"}"
      }
      create_dc "dc_tenant_id" "Billing Tenant ID"
      create_dc "dc_isolation_model" "Tenancy Architecture Model"

      # Create Custom Billing Report
      curl -s -X POST "https://apigee.googleapis.com/v1/organizations/$ORG/reports" \
        -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
        -d '{
          "name": "tenant_billing_report",
          "displayName": "Tenant Billing Dashboard",
          "metrics": [{"name": "message_count", "function": "sum"}],
          "dimensions": ["dc_tenant_id", "dc_isolation_model", "apiproxy"],
          "chartType": "column"
        }'
EOF
  }
}

# ==============================================================================
# PRIVATE DNS (Routing to PSC Endpoint)
# ==============================================================================

data "google_compute_network" "default_network" {
  name    = "default"
  project = var.gcp_project_id
}

resource "google_dns_managed_zone" "apigee_private_zone" {
  name        = "apigee-private-zone-psc"
  project     = var.gcp_project_id
  dns_name    = "${var.base_domain}."
  visibility  = "private"
  private_visibility_config {
    networks { network_url = data.google_compute_network.default_network.id }
  }
  depends_on = [google_project_service.dns_api]
}

resource "google_dns_record_set" "model_a_records" {
  for_each     = var.model_a_tenants
  project      = var.gcp_project_id
  managed_zone = google_dns_managed_zone.apigee_private_zone.name
  name         = "${each.value.hostname}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.apigee_psc_endpoint_ip.address]
}

resource "google_dns_record_set" "model_b_records" {
  for_each     = var.model_b_tenants
  project      = var.gcp_project_id
  managed_zone = google_dns_managed_zone.apigee_private_zone.name
  name         = "${each.value.hostname}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_address.apigee_psc_endpoint_ip.address]
}

# ==============================================================================
# TEST INFRASTRUCTURE
# ==============================================================================

resource "google_compute_instance" "apigee_test_vm" {
  name         = "apigee-test-vm-psc"
  project      = var.gcp_project_id
  machine_type = "e2-micro"
  zone         = "${var.gcp_region}-a"

  boot_disk {
    initialize_params { image = "debian-cloud/debian-12" }
  }

  network_interface {
    network = "default"
    access_config {} # Ephemeral public IP for SSH
  }

  depends_on = [google_project_service.compute_api]
}