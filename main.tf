data "aws_region" "current" {}

locals {
  litellm_base_url   = "http://litellm.${aws_service_discovery_private_dns_namespace.app.name}:4000/v1"
  litellm_master_key = "sk-${var.project_name}-litellm"

  models_config = yamldecode(file("${path.module}/config/models.yaml"))

  litellm_model_list = concat(
    [
      for name, model in try(local.models_config.chat, {}) : {
        model_name = try(model.alias, name)
        model      = "bedrock/${model.id}"
      }
    ]
  )

  litellm_config = templatefile("${path.module}/config/litellm-config.yaml.tftpl", {
    aws_region = var.aws_region
    model_list = local.litellm_model_list
  })
}

resource "aws_vpc" "app" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = cidrsubnet(aws_vpc.app.cidr_block, 8, 0)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_cloudwatch_log_group" "open_webui" {
  name              = "/ecs/${var.project_name}-open-webui"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "litellm" {
  name              = "/ecs/${var.project_name}-litellm"
  retention_in_days = 7
}

resource "aws_security_group" "ecs_task" {
  name        = "${var.project_name}-ecs-task-sg"
  description = "Allow internet traffic to Open WebUI"
  vpc_id      = aws_vpc.app.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "litellm" {
  name        = "${var.project_name}-litellm-sg"
  description = "Allow Open WebUI to reach LiteLLM"
  vpc_id      = aws_vpc.app.id

  ingress {
    description     = "Open WebUI to LiteLLM"
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_task.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_litellm" {
  name = "${var.project_name}-ecs-task-litellm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_litellm_bedrock" {
  name = "${var.project_name}-ecs-task-litellm-bedrock"
  role = aws_iam_role.ecs_task_litellm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:Converse",
          "bedrock:ConverseStream",
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationModels",
          "bedrock:GetFoundationModel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"

  setting {
    name = "containerInsights"
    # disabled, enabled, enhanced
    value = "disabled"
  }
}

resource "aws_service_discovery_private_dns_namespace" "app" {
  name = "${var.project_name}.local"
  vpc  = aws_vpc.app.id
}

resource "aws_service_discovery_service" "litellm" {
  name = "litellm"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.app.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ecs_task_definition" "open_webui" {
  family                   = "${var.project_name}-open-webui"
  cpu                      = 512
  memory                   = 2048
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

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

resource "aws_ecs_task_definition" "litellm" {
  family                   = "${var.project_name}-litellm"
  cpu                      = 512
  memory                   = 1024
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_litellm.arn

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
        },
        {
          name  = "LITELLM_MASTER_KEY"
          value = local.litellm_master_key
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

resource "aws_ecs_service" "open_webui" {
  name            = "${var.project_name}-open-webui"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.open_webui.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public.id]
    security_groups  = [aws_security_group.ecs_task.id]
    assign_public_ip = true
  }
}

resource "aws_ecs_service" "litellm" {
  name            = "${var.project_name}-litellm"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.litellm.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  service_registries {
    registry_arn = aws_service_discovery_service.litellm.arn
  }

  network_configuration {
    subnets          = [aws_subnet.public.id]
    security_groups  = [aws_security_group.litellm.id]
    assign_public_ip = true
  }
}
