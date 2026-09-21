variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-west-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "my-project"
}

variable "budget_notification_email" {
  description = "Email address that receives AWS Budget alerts"
  type        = string
}

variable "domain_name" {
  description = "Root domain name, delegated to Route 53, used for ALB routing and ACM certificate"
  type        = string
}