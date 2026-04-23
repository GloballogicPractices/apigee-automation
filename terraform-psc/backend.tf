# Uncomment and configure this block once you have created a GCS bucket
terraform {
  backend "gcs" {
    bucket = "490614-infratest-gl"
    prefix = "apigee/psc-tenancy-state"
  }
}

