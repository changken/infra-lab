#==============================================================
# Secrets Manager（原生注入 Task Definition）
#
# EKS vs ECS 密鑰管理對比：
#   EKS (ESO):   ExternalSecret CR → K8s Secret → Pod env var
#                需要: ESO operator + ClusterSecretStore + ExternalSecret YAML
#   ECS Fargate: Task Definition 的 secrets block 直接引用 Secrets Manager ARN
#                ECS Agent 在 task 啟動時自動注入，無需額外 operator
#
# 安全特性：
#   - 密鑰值不存入 Terraform state（只存 ARN）
#   - Task execution role 有明確的 GetSecretValue 授權
#   - 容器看到的是環境變數，不需要 mount 任何 volume
#==============================================================

resource "aws_secretsmanager_secret" "app_config" {
  name        = "${local.name_prefix}/ecs/app-config"
  description = "ECS app configuration (injected as env vars into task)"

  recovery_window_in_days = 0 # lab 環境：destroy 時立即刪除，不需要 7 天冷卻

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "app_config" {
  secret_id = aws_secretsmanager_secret.app_config.id

  # JSON 格式可以在 task definition 中用 key 選取單一欄位
  # 例如：valueFrom = "${arn}:API_KEY::"  → 只注入 API_KEY 值
  secret_string = jsonencode({
    API_KEY     = "changeme-replace-with-real-secret"
    DB_PASSWORD = "changeme-replace-with-real-secret"
  })
}
