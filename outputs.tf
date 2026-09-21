output "open_webui_url" {
  description = "Open WebUI URL exposed through the ALB"
  value       = "https://app.${var.domain_name}"
}

output "litellm_api_url" {
  description = "LiteLLM API URL exposed through the ALB"
  value       = "https://api.${var.domain_name}"
}