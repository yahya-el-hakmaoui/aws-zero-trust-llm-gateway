output "open_webui_url" {
  description = "Open WebUI endpoint pattern (task public IP on port 80)"
  value       = "http://<ecs-task-public-ip>"
}

output "vpc_id" {
  description = "ID of the dedicated VPC"
  value       = aws_vpc.app.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets used by the ALB and ECS service"
  value       = [aws_subnet.public.id]
}