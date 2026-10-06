resource "aws_ecs_task_definition" "litellm" {
  family                   = "${var.project_name}-litellm"
  cpu                      = 512
  memory                   = 1024
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_litellm.arn

  container_definitions = jsonencode([
    {
      name       = "litellm"
      image      = "ghcr.io/berriai/litellm:latest"
      essential  = true
      entryPoint = ["sh", "-lc"]
      command = [
        <<-EOT
cat >/tmp/config.yaml <<'EOF'
${local.litellm_config}
EOF
exec litellm --config /tmp/config.yaml --host 0.0.0.0 --port 4000
EOT
      ]
      environment = [
        {
          name  = "AWS_REGION_NAME"
          value = var.aws_region
        }
      ]
      secrets = [
        {
          name      = "LITELLM_MASTER_KEY"
          valueFrom = aws_secretsmanager_secret.litellm_master.arn
        }
      ]
      portMappings = [
        {
          containerPort = 4000
          hostPort      = 4000
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.litellm.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "litellm" {
  name            = "${var.project_name}-litellm"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.litellm.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  depends_on = [aws_iam_role_policy.ecs_task_execution_secrets]

  service_registries {
    registry_arn = aws_service_discovery_service.litellm.arn
  }

  network_configuration {
    subnets          = [for subnet in aws_subnet.private : subnet.id]
    security_groups  = [aws_security_group.litellm.id]
    assign_public_ip = false
  }
}