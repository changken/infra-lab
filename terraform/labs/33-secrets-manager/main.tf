#==============================================================
# 學習目標：Secrets Manager + KMS CMK + Lambda 自動輪換
#
# 核心問題：如何讓 AWS 自動輪換資料庫密碼，不需人工介入？
#
# Secrets Manager 版本標籤（面試必考）：
#   AWSCURRENT  → 目前使用的版本
#   AWSPENDING  → 輪換中，尚未升格
#   AWSPREVIOUS → 上一個版本（保留供回滾）
#
# Rotation Lambda 4 步驟（面試必考）：
#   createSecret  → 產生新密碼，寫入 AWSPENDING 版本
#   setSecret     → 在真實資源（DB）上套用新密碼（本 lab 為 no-op）
#   testSecret    → 驗證新密碼可用
#   finishSecret  → AWSPENDING 升格為 AWSCURRENT
#
# KMS CMK vs AWS 受管金鑰：
#   AWS 受管金鑰（aws/secretsmanager）→ 免費，但無法自訂 key policy
#   CMK（Customer Managed Key）      → $1/月，可停用、可稽核、可跨帳號
#   → 本 lab 使用 CMK，學習 key policy 設計
#
# 完成順序：1 → 2 → 3 → 4 → 5 → 6
#==============================================================


# 已完成：取得目前 AWS 帳號 ID（IAM policy 需要用到）
data "aws_caller_identity" "current" {}

# 已完成：打包 Lambda 原始碼
data "archive_file" "rotation" {
  type        = "zip"
  source_file = "${path.module}/src/rotation_handler.py"
  output_path = "${path.module}/src/rotation_handler.zip"
}


#--------------------------------------------------------------
# TODO 1: KMS CMK + Alias
#--------------------------------------------------------------
# 文件 (key):   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key
# 文件 (alias): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias
#
# [KMS Key]
#   description             = "KMS key for Secrets Manager lab"
#   enable_key_rotation     = true   # ← AWS 每年自動輪換 key material（非 secret 輪換）
#   deletion_window_in_days = 7      # ← destroy 後 7 天才真正刪除，防止誤刪
#   tags                    = local.common_tags
#
# [KMS Alias]
#   name          = "alias/${var.project}-key"
#   target_key_id = aws_kms_key.main.key_id

resource "aws_kms_key" "main" {
  # TODO
  description             = "KMS key for Secrets Manager lab"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = local.common_tags
}

resource "aws_kms_alias" "main" {
  # TODO
  name          = "alias/${var.project}-key"
  target_key_id = aws_kms_key.main.key_id
}


#--------------------------------------------------------------
# TODO 2: Lambda IAM Role（含 SecretsManager + KMS 權限）
#--------------------------------------------------------------
# 文件 (role):             https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
# 文件 (policy_attachment): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
# 文件 (inline_policy):     https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
#
# [IAM Role]
#   name = "${var.project}-rotation-role"
#   tags = local.common_tags
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "lambda.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
#
# [Policy Attachment：CloudWatch Logs]
#   role       = aws_iam_role.rotation.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
#
# [Inline Policy：SecretsManager + KMS]
#   name = "${var.project}-rotation-policy"
#   role = aws_iam_role.rotation.id
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "secretsmanager:GetSecretValue",
#           "secretsmanager:PutSecretValue",
#           "secretsmanager:DescribeSecret",
#           "secretsmanager:UpdateSecretVersionStage",
#         ]
#         # ← Secrets Manager 會在 ARN 後加隨機後綴，故用萬用字元 -* 匹配
#         Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.project}-db-credentials-*"
#       },
#       {
#         Effect   = "Allow"
#         Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
#         Resource = aws_kms_key.main.arn
#       },
#     ]
#   })
#
# ⚠️ 注意：IAM Policy 的 Resource 不能用 "*" 而應鎖定到特定 ARN（最小權限原則）

resource "aws_iam_role" "rotation" {
  # TODO
  name = "${var.project}-rotation-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rotation_basic" {
  # TODO
  role       = aws_iam_role.rotation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "rotation" {
  # TODO
  name = "${var.project}-rotation-policy"
  role = aws_iam_role.rotation.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:UpdateSecretVersionStage",
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.project}-db-credentials-*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.main.arn
      },
    ]
  })
}


#--------------------------------------------------------------
# TODO 3: Lambda Function（Rotation Handler）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
#
#   function_name    = "${var.project}-rotation"
#   runtime          = "python3.12"
#   handler          = "rotation_handler.handler"
#   role             = aws_iam_role.rotation.arn
#   filename         = data.archive_file.rotation.output_path
#   source_code_hash = data.archive_file.rotation.output_base64sha256
#   tags             = local.common_tags
#
#   environment {
#     variables = {
#       SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.region}.amazonaws.com"
#       # ← rotation Lambda 需要知道 endpoint 才能呼叫 SecretsManager API
#     }
#   }

resource "aws_lambda_function" "rotation" {
  # TODO
  function_name    = "${var.project}-rotation"
  runtime          = "python3.12"
  handler          = "rotation_handler.handler"
  role             = aws_iam_role.rotation.arn
  filename         = data.archive_file.rotation.output_path
  source_code_hash = data.archive_file.rotation.output_base64sha256
  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.region}.amazonaws.com"
    }
  }
  tags = local.common_tags
}


#--------------------------------------------------------------
# TODO 4: Lambda Permission（允許 Secrets Manager 呼叫 Lambda）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission
#
#   statement_id  = "AllowSecretsManagerInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.rotation.function_name
#   principal     = "secretsmanager.amazonaws.com"
#   source_account = data.aws_caller_identity.current.account_id
#   # ← source_account 限制只有本帳號的 Secrets Manager 可以呼叫此 Lambda
#
# ⚠️ 注意：principal 是 "secretsmanager.amazonaws.com"，不是 "lambda.amazonaws.com"

resource "aws_lambda_permission" "secretsmanager" {
  # TODO
  statement_id   = "AllowSecretsManagerInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.rotation.function_name
  principal      = "secretsmanager.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}


#--------------------------------------------------------------
# TODO 5: Secrets Manager Secret + 初始版本
#--------------------------------------------------------------
# 文件 (secret):         https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret
# 文件 (secret_version): https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version
#
# [Secret]
#   name        = "${var.project}-db-credentials"
#   description = "Database credentials for lab"
#   kms_key_id  = aws_kms_key.main.arn   # ← 使用 CMK 加密
#   tags        = local.common_tags
#
#   recovery_window_in_days = 0
#   # ← 設為 0 讓 terraform destroy 能立刻刪除 secret
#   # ← 預設是 30 天恢復期，destroy 後資源還在，重新 apply 會衝突
#
# [Secret Version（初始密碼）]
#   secret_id = aws_secretsmanager_secret.db.id
#   secret_string = jsonencode({
#     username = "admin"
#     password = "InitialPassword123!"
#   })
#
# ⚠️ 注意：secret 名稱後 AWS 會自動加 6 碼隨機字元（例如 -abc123），
#          這就是為什麼 IAM policy 的 Resource 結尾需要 -*

resource "aws_secretsmanager_secret" "db" {
  # TODO
  name                    = "${var.project}-db-credentials"
  description             = "Database credentials for lab"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "initial" {
  # TODO
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = "admin"
    password = "InitialPassword123!"
  })
}


#--------------------------------------------------------------
# TODO 6: Secrets Manager 自動輪換設定
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_rotation
#
#   secret_id           = aws_secretsmanager_secret.db.id
#   rotation_lambda_arn = aws_lambda_function.rotation.arn
#
#   rotation_rules {
#     automatically_after_days = 1
#     # ← lab 設 1 天方便測試；生產環境建議 30-90 天
#   }
#
# ⚠️ 注意：設定 rotation 後，AWS 預設會立刻觸發一次輪換（rotate_immediately = true）
#          apply 後約 10-30 秒密碼即已更換，驗證時讀到的不是 InitialPassword123!
#          若不想立即輪換，可加 rotate_immediately = false（但 lab 建議保留立即輪換以便驗證）
#
#   depends_on = [aws_lambda_permission.secretsmanager]
#   # ← 必要！確保 Lambda permission 建立後才啟用輪換
#   # ← 若缺少此設定，立即觸發的輪換會因 Lambda 尚無 invoke 權限而 AccessDenied
#   # ← 參考 S3 notification 的相同模式（CLAUDE.md 卡關提示）

resource "aws_secretsmanager_secret_rotation" "db" {
  # TODO
  secret_id           = aws_secretsmanager_secret.db.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  rotation_rules {
    automatically_after_days = 1
  }
  depends_on = [aws_lambda_permission.secretsmanager]
}
