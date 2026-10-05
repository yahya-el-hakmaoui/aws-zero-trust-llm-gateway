output "open_webui_url" {
  description = "Open WebUI URL exposed through the ALB"
  value       = "https://${var.domain_name}"
}