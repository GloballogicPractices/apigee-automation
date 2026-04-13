# Output the API Keys to securely pass back to the tenants
output "tenant_api_keys" {
  value = {
    for k, v in google_apigee_developer_app.shared_tenant_apps : k => v.credentials.consumer_key
  }
  sensitive = true
}