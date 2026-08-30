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