terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0" # Latest major version for best Apigee support
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
  }

  # Recommended: Store your state in a GCS bucket
  backend "gcs" {
    bucket = "490614-infratest"
    prefix = "terraform/state/apigee-infra"
  }
}

provider "google" {
  project = "apigee-490614"
  region  = "us-central1" # Replace with your primary region
}

provider "google-beta" {
  project = "apigee-490614"
  region  = "us-central1"
}

# Data source to access the project ID or number elsewhere in your code
data "google_client_config" "current" {}