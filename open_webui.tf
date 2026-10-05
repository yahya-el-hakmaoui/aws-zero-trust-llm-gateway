resource "aws_ecs_task_definition" "open_webui" {
  family                   = "${var.project_name}-open-webui"
  cpu                      = 512
  memory                   = 2048
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  execution_role_arn = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "open-webui"
      image     = "ghcr.io/open-webui/open-webui:main"
      essential = true
      environment = [
        {
          name  = "PORT"
          value = "80"
        },
        {
          name  = "OPENAI_API_BASE_URL"
          value = local.litellm_base_url
        },
        {
          name  = "OPENAI_API_KEY"
          value = local.litellm_master_key
        }
      ]
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.open_webui.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "open_webui" {
  name            = "${var.project_name}-open-webui"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.open_webui.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.open_webui.arn
    container_name   = "open-webui"
    container_port   = 80
  }

  network_configuration {
    subnets          = [for subnet in aws_subnet.private : subnet.id]
    security_groups  = [aws_security_group.ecs_task.id]
    assign_public_ip = false
  }
}