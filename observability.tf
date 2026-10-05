resource "aws_cloudwatch_log_group" "open_webui" {
  name              = "/ecs/${var.project_name}-open-webui"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "litellm" {
  name              = "/ecs/${var.project_name}-litellm"
  retention_in_days = 7
}