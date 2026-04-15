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

  # Force Terraform to enable the API before trying to create the Org
  # depends_on = [google_project_service.apigee_api] 
  # UPDATE THIS LINE: Use the absolute path to your VPC network
  authorized_network = "projects/${var.gcp_project_id}/global/networks/default" 
  
  billing_type       = "EVALUATION" 

  depends_on = [
    google_service_networking_connection.apigee_vpc_connection
  ]
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
  hostnames = [for tenant in var.model_b_tenants : tenant.hostname]
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

 # ==============================================================
  # QUOTA LIMITS
  # ==============================================================
  # This configuration enforces a limit of 100 requests per minute
  # across all APIs assigned to this specific product.
  quota           = "100"
  quota_interval  = "1"
  quota_time_unit = "minute" # Accepted values: minute, hour, day, month

  # ==============================================================
  # OPERATION GROUP (Corrected Syntax)
  # ==============================================================
  operation_group {
    
    # Your first proxy bundle (Hello World)
    operation_configs {
      api_source = "helloworld"
      
      operations {
        resource = "/"
        methods  = ["GET", "POST", "PUT", "DELETE"]
      }
    }

    # Your second proxy bundle (Payments API)
    # operation_configs {
    #   api_source = "payments-api"
      
    #   operations {
    #     resource = "/"
    #     methods  = ["GET", "POST"]
    #   }
    # }
    
  }
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
  org_id        = google_apigee_organization.apigee_org.id
  name          = "product-${each.key}"
  display_name  = "Premium Tier - ${each.key}"
  environments  = [google_apigee_environment.model_a_envs[each.key].name]
  approval_type = "auto"
  # ==============================================================
  # QUOTA LIMITS
  # ==============================================================
  # This configuration enforces a limit of 100 requests per minute
  # across all APIs assigned to this specific product.
  quota           = "100"
  quota_interval  = "1"
  quota_time_unit = "minute" # Accepted values: minute, hour, day, month

  # ==============================================================
  # OPERATION GROUP (Corrected Syntax)
  # ==============================================================
  operation_group {
    
    # Your first proxy bundle (Hello World)
    operation_configs {
      api_source = "helloworld"
      
      operations {
        resource = "/"
        methods  = ["GET", "POST", "PUT", "DELETE"]
      }
    }

    # Your second proxy bundle (Payments API)
    # operation_configs {
    #   api_source = "payments-api"
      
    #   operations {
    #     resource = "/"
    #     methods  = ["GET", "POST"]
    #   }
    # }
    
  }

  depends_on = [google_apigee_instance_attachment.model_a_instance_attach]
}

# 6. Create Model A Developers
resource "google_apigee_developer" "model_a_devs" {
  for_each   = var.model_a_tenants
  org_id     = google_apigee_organization.apigee_org.id
  email      = each.value.dev_email
  first_name = "Admin"
  last_name  = each.key
  user_name  = each.key
}

# 7. Create Model A Apps (With attributes for billing parity)
resource "google_apigee_developer_app" "model_a_apps" {
  for_each        = var.model_a_tenants
  org_id          = google_apigee_organization.apigee_org.id
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

# ==============================================================================
# APIGEE DATA COLLECTORS 
# ==============================================================================

resource "null_resource" "apigee_data_collectors" {
  # CRITICAL: This ensures Terraform builds the Org before trying to add collectors
  depends_on = [google_apigee_organization.apigee_org]

  triggers = {
    # If your project ID changes, Terraform knows it must re-run this script
    project_id = var.gcp_project_id
  }

  provisioner "local-exec" {
    command = <<EOF
      #!/bin/bash
      # 1. Grab the active token from the environment
      TOKEN=$(gcloud auth print-access-token)
      ORG="${var.gcp_project_id}"

      # 2. Define a function to safely create collectors
      create_collector() {
        NAME=$1
        DESC=$2
        
        echo "Checking if $NAME exists..."
        # We use %%{http_code} because Terraform requires escaping the % symbol
        HTTP_STATUS=$(curl -s -o /dev/null -w "%%{http_code}" -H "Authorization: Bearer $TOKEN" "https://apigee.googleapis.com/v1/organizations/$ORG/datacollectors/$NAME")
        
        if [ "$HTTP_STATUS" -eq 404 ]; then
          echo "Collector not found. Creating $NAME..."
          curl -s -X POST "https://apigee.googleapis.com/v1/organizations/$ORG/datacollectors" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"$NAME\", \"type\": \"STRING\", \"description\": \"$DESC\"}"
          echo " Successfully created!"
        else
          echo "Data Collector $NAME already exists. Skipping creation."
        fi
      }

      # 3. Execute the function for our specific billing requirements
      create_collector "dc_tenant_id" "Captures the Tenant ID for billing"
      create_collector "dc_isolation_model" "Captures the Architecture Model"
    EOF
  }
}

# ==============================================================================
# INTERNAL TEST VM
# ==============================================================================

resource "google_compute_instance" "apigee_test_vm" {
  name         = "apigee-test-vm"
  project      = var.gcp_project_id
  machine_type = "e2-micro"
  zone         = "us-central1-a" # Ensure this matches the region you are deploying to

  boot_disk {
    initialize_params {
      # Use a standard, lightweight Debian Linux image
      image = "debian-cloud/debian-12" 
    }
  }

  network_interface {
    network = "default"
    
    # This empty block assigns an ephemeral public IP so you can SSH into it.
    # Without this, the VM is completely isolated from the internet!
    access_config {
      // Ephemeral public IP
    }
  }

  # Ensure the Compute API is enabled before trying to build a VM
  depends_on = [google_project_service.compute_api]
}

## ==============================================================================
# APIGEE CUSTOM ANALYTICS REPORT (BILLING)
# ==============================================================================

resource "null_resource" "apigee_tenant_billing_report" {
  # CRITICAL: The data collectors must exist before a report can reference them!
  depends_on = [null_resource.apigee_data_collectors]

  triggers = {
    # Re-run if the project ID ever changes
    project_id = var.gcp_project_id
  }

  provisioner "local-exec" {
    command = <<EOF
      #!/bin/bash
      # 1. Grab auth token and set variables
      TOKEN=$(gcloud auth print-access-token)
      ORG="${var.gcp_project_id}"
      REPORT_NAME="tenant_billing_validation"
      
      echo "Checking if Billing Custom Report exists..."
      
      # 2. Check if the report is already built (Idempotency check)
      HTTP_STATUS=$(curl -s -o /dev/null -w "%%{http_code}" -H "Authorization: Bearer $TOKEN" "https://apigee.googleapis.com/v1/organizations/$ORG/reports/$REPORT_NAME")
      
      if [ "$HTTP_STATUS" -eq 404 ]; then
        echo "Creating Tenant Billing Custom Report..."
        
        # 3. Define the Report Configuration JSON (REMOVED DESCRIPTION FIELD)
        # message_count = Total Traffic
        # dimensions = Our custom attributes + the name of the API proxy
        cat << 'JSON_EOF' > report_payload.json
        {
          "name": "tenant_billing_validation",
          "displayName": "Tenant Billing Validation (Auto-Generated)",
          "metrics": [
            {
              "name": "message_count",
              "function": "sum"
            }
          ],
          "dimensions": [
            "dc_tenant_id",
            "dc_isolation_model",
            "apiproxy"
          ],
          "chartType": "column"
        }
JSON_EOF

        # 4. Push the configuration to the Apigee Management API
        curl -s -X POST "https://apigee.googleapis.com/v1/organizations/$ORG/reports" \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -d @report_payload.json
          
        rm report_payload.json
        echo -e "\nReport created successfully!"
      else
        echo "Report $REPORT_NAME already exists. Skipping creation."
      fi
    EOF
  }
}
# ==============================================================================
# 1. ENABLE CLOUD DNS API
# ==============================================================================
resource "google_project_service" "dns_api" {
  project            = var.gcp_project_id
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

# ==============================================================================
# 2. FETCH EXISTING VPC NETWORK
# ==============================================================================
# This ensures we attach the private DNS zone to the same network as your test VM
data "google_compute_network" "default_network" {
  name    = "default"
  project = var.gcp_project_id
}

# ==============================================================================
# 3. CREATE THE PRIVATE DNS ZONE
# ==============================================================================
resource "google_dns_managed_zone" "apigee_private_zone" {
  name        = "apigee-private-zone"
  project     = var.gcp_project_id
  
  # CRITICAL: The base domain must end with a trailing dot
  dns_name    = "${var.base_domain}."


  description = "Private DNS zone for internal multi-tenant Apigee routing"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = data.google_compute_network.default_network.id
    }
  }

  depends_on = [google_project_service.dns_api]
}

# ==============================================================================
# 4. EXPLICIT DNS RECORDS FOR MODEL A (DEDICATED TENANTS)
# ==============================================================================
resource "google_dns_record_set" "model_a_records" {
  # Loops through the map, building a unique DNS record for each premium tenant
  for_each = var.model_a_tenants

  project      = var.gcp_project_id
  managed_zone = google_dns_managed_zone.apigee_private_zone.name
  
  # Dynamically pull the hostname from the variable and append the required trailing dot
  name         = "${each.value.hostname}." 
  type         = "A"
  ttl          = 300
  
  # Points directly to the Apigee Internal IP
  rrdatas = [google_apigee_instance.apigee_instance.host]
}

# ==============================================================================
# EXPLICIT DNS RECORDS FOR MODEL B (SHARED POOL TENANTS)
# ==============================================================================
resource "google_dns_record_set" "model_b_records" {
  # Loops through every tenant in the shared pool map
  for_each = var.model_b_tenants

  project      = var.gcp_project_id
  managed_zone = google_dns_managed_zone.apigee_private_zone.name
  
  # Dynamically pulls the vanity hostname and appends the trailing dot
  name         = "${each.value.hostname}." 
  type         = "A"
  ttl          = 300
  
  # Points directly to the shared Apigee Internal Gateway IP
  rrdatas = [google_apigee_instance.apigee_instance.host]
}