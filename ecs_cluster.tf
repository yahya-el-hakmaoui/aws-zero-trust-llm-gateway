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