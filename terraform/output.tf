output "model_a_api_keys" {
  description = "API Keys for Premium Dedicated Tenants"
  value = {
    # Notice the added after credentials
    for k, v in google_apigee_developer_app.model_a_apps : k => v.credentials.consumer_key
  }
  sensitive = true
}

output "model_b_api_keys" {
  description = "API Keys for Standard Shared Tenants"
  value = {
    # Notice the added after credentials
    for k, v in google_apigee_developer_app.model_b_apps : k => v.credentials.consumer_key
  }
  sensitive = true
}