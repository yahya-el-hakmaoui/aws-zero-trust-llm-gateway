ephemeral "random_password" "litellm_master" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "litellm_master" {
  name = "${var.project_name}/litellm/master-key"

  # PoC : permet de détruire puis recréer le secret sans attendre 30 jours.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "litellm_master" {
  secret_id                = aws_secretsmanager_secret.litellm_master.id
  secret_string_wo         = "sk-${ephemeral.random_password.litellm_master.result}"
  secret_string_wo_version = 1
}