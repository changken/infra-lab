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

resource "aws_iam_role_policy" "custom_app_bedrock" {
  name = "${local.name_prefix}-custom-app-bedrock"
  role = aws_iam_role.custom_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:Converse"
      ]
      # us.* inference profiles route across us-east-1/us-east-2/us-west-2
      # region wildcard is required; model/profile IDs are explicitly locked
      Resource = [
        "arn:aws:bedrock:*::foundation-model/amazon.nova-lite-v1:0",
        "arn:aws:bedrock:*::foundation-model/meta.llama3-1-8b-instruct-v1:0",
        "arn:aws:bedrock:*::foundation-model/deepseek.r1-v1:0",
        "arn:aws:bedrock:*::foundation-model/meta.llama4-scout-17b-instruct-v1:0",
        "arn:aws:bedrock:*::foundation-model/mistral.mistral-large-2402-v1:0",
        "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.amazon.nova-lite-v1:0",
        "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.meta.llama3-1-8b-instruct-v1:0",
        "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.deepseek.r1-v1:0",
        "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.meta.llama4-scout-17b-instruct-v1:0",
      ]
    }]
  })
}

output "custom_app_role_arn" {
  description = "custom-app IRSA Role ARN（ServiceAccount annotation 用）"
  value       = aws_iam_role.custom_app.arn
}
