#==============================================================
# External Secrets Operator (ESO) — AWS Secrets Manager 整合
#
# 流程：
#   ExternalSecret CRD
#     └── ClusterSecretStore（aws provider）
#           └── ESO controller（IRSA → Secrets Manager GetSecretValue）
#                 └── 自動建立 / 同步 K8s Secret
#
# 安全優勢：
#   - K8s Secret 由 ESO 管理，不手動建立也不 commit 值
#   - Secrets Manager 支援自動 rotation
#   - IRSA 限制只有 ESO SA 能讀指定 secret
#==============================================================

# ── AWS Secrets Manager Secret ───────────────────────────────

resource "aws_secretsmanager_secret" "custom_app" {
  name        = "${local.name_prefix}/custom-app"
  description = "custom-app 應用程式的 API keys（由 ESO 同步至 K8s）"

  # 防止意外刪除（destroy 時需先手動關掉）
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "custom_app" {
  secret_id = aws_secretsmanager_secret.custom_app.id

  # 初始佔位值，實際 key 請到 Secrets Manager console 更新
  secret_string = jsonencode({
    chat-api-key = "demo-lab-key-9f5d36bc5a62449d"
  })

  lifecycle {
    # 避免 terraform apply 覆蓋掉 console 手動更新的值
    ignore_changes = [secret_string]
  }
}

# ── ESO IRSA Role ─────────────────────────────────────────────
# ESO controller 使用此 role 向 Secrets Manager 取得 secret 值

resource "aws_iam_role" "eso" {
  name = "${local.name_prefix}-eso-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          # 鎖定 ESO controller 的 ServiceAccount
          "${local.oidc_issuer}:sub" = "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "eso_secrets" {
  name        = "${local.name_prefix}-eso-secrets"
  description = "ESO: 只允許讀取 custom-app secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGetSecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        # 只允許此 secret，不開放所有 secrets
        Resource = aws_secretsmanager_secret.custom_app.arn
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso_secrets.arn
}

# ── Outputs ──────────────────────────────────────────────────

output "eso_role_arn" {
  description = "ESO IRSA Role ARN → helm install 時的 serviceAccount.annotations"
  value       = aws_iam_role.eso.arn
}

output "eso_secret_name" {
  description = "AWS Secrets Manager secret name"
  value       = aws_secretsmanager_secret.custom_app.name
}

output "eso_helm_command" {
  description = "安裝 ESO 的 Helm 指令"
  value       = <<-EOT
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update
    helm install external-secrets external-secrets/external-secrets \
      -n external-secrets --create-namespace \
      --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${aws_iam_role.eso.arn}
  EOT
}
