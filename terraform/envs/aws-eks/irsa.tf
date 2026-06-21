#==============================================================
# IRSA — custom-app IAM Role
#
# 讓 custom-app Pod 透過 Kubernetes ServiceAccount 取得 AWS 權限，
# 不需要 hardcode Access Key / Secret Key。
#
# 信任鏈：
#   Pod → ServiceAccount → OIDC → IAM Role → AWS API
#==============================================================

resource "aws_iam_role" "custom_app" {
  name = "${local.name_prefix}-custom-app-role"

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
          "${local.oidc_issuer}:sub" = "system:serviceaccount:custom-app:custom-app"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "custom_app_s3" {
  name = "${local.name_prefix}-custom-app-s3"
  role = aws_iam_role.custom_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListAllMyBuckets"]
      Resource = "*"
    }]
  })
}

output "custom_app_role_arn" {
  description = "custom-app IRSA Role ARN（ServiceAccount annotation 用）"
  value       = aws_iam_role.custom_app.arn
}
