output "open_webui_url" {
  description = "Open WebUI URL exposed through the ALB"
  value       = "http://${aws_lb.app.dns_name}"
}