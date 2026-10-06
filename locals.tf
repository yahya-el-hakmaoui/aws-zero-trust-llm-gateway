data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  litellm_base_url   = "http://litellm.${aws_service_discovery_private_dns_namespace.app.name}:4000/v1"
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)

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