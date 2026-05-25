#==============================================================
# 學習目標：Cognito User Pool + App Client + JWT 驗證
#
# 核心問題：如何用 AWS 原生服務管理使用者身份，
#           而不需要自己實作認證系統？
#
# Cognito 兩大元件（面試必考）：
#   User Pool    → 管理使用者帳號、密碼、JWT Token
#                → 你在這個 lab 用的就是這個
#   Identity Pool → 把 JWT 換成 AWS 臨時憑證（STS）
#                → 讓使用者直接存取 S3/DynamoDB（Lab 40 主題）
#
# JWT Token 三種類型（面試必考）：
#   ID Token      → 包含使用者屬性（email, sub 等）
#                 → 向你的 API 證明「我是誰」
#   Access Token  → 包含 OAuth2 Scope，用於 API 授權
#                 → 不包含 email 等用戶屬性
#   Refresh Token → 換取新的 ID/Access Token，有效期較長
#                 → 不要傳給前端 API
#
# App Client generate_secret：
#   false → SPA、Mobile App、CLI（本 lab 用這個）
#   true  → Server-side Web App（需要安全儲存 secret）
#   → CLI 無法安全儲存 secret，所以本 lab 用 false
#
# 認證流程選擇：
#   USER_PASSWORD_AUTH → 直接傳 username + password（適合 lab）
#   SRP_AUTH           → Secure Remote Password，不傳明文（生產環境）
#
# 完成順序：1 → 2 → 3
#==============================================================


# 已完成：取得目前 AWS Account ID（確保 User Pool Domain 全域唯一）
data "aws_caller_identity" "current" {}


#--------------------------------------------------------------
# TODO 1: Cognito User Pool
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool
#
#   name = "${var.project}-pool"
#
#   username_attributes      = ["email"]
#   # ← 使用 email 作為 username，使用者不需要另設帳號名稱
#
#   auto_verified_attributes = ["email"]
#   # ← admin 建立用戶後，email 自動標記為已驗證
#   #   若使用者自行註冊，Cognito 會寄送驗證信
#
#   password_policy {
#     minimum_length    = 8
#     require_uppercase = true
#     require_lowercase = true
#     require_numbers   = true
#     require_symbols   = true
#   }
#
#   admin_create_user_config {
#     allow_admin_create_user_only = false
#     # ← false：使用者可自行註冊
#     # ← true：只能由管理員建立帳號（企業內部系統常用）
#   }
#
#   tags = local.common_tags

resource "aws_cognito_user_pool" "main" {
  # TODO
}


#--------------------------------------------------------------
# TODO 2: Cognito User Pool Client（App Client）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client
#
#   name         = "${var.project}-client"
#   user_pool_id = aws_cognito_user_pool.main.id
#
#   generate_secret = false
#   # ← CLI 和 SPA 無法安全儲存 client secret，設 false
#   # ← Server-side app 設 true，secret 儲存在後端
#
#   explicit_auth_flows = [
#     "ALLOW_USER_PASSWORD_AUTH",
#     # ← 允許直接用 username + password 換 token（本 lab 需要）
#     "ALLOW_REFRESH_TOKEN_AUTH",
#     # ← 允許用 Refresh Token 換新的 Access/ID Token
#   ]
#
#   # Token 有效期（選填，以下為合理預設值）
#   access_token_validity  = 60   # 分鐘
#   id_token_validity      = 60   # 分鐘
#   refresh_token_validity = 30   # 天
#
#   token_validity_units {
#     access_token  = "minutes"
#     id_token      = "minutes"
#     refresh_token = "days"
#   }

resource "aws_cognito_user_pool_client" "app" {
  # TODO
}


#--------------------------------------------------------------
# TODO 3: Cognito User Pool Domain
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_domain
#
# Hosted UI 網址格式：
#   https://<domain>.auth.<region>.amazoncognito.com/login
#
# ⚠️ domain prefix 在整個 AWS 全域必須唯一！
#    使用 Account ID 後 8 碼避免與其他帳號衝突：
#
#   domain       = "${var.project}-${substr(data.aws_caller_identity.current.account_id, -8, -1)}"
#   user_pool_id = aws_cognito_user_pool.main.id
#
# 本 lab 不實際使用 Hosted UI，但這是 Lab 40（API GW + Cognito Authorizer）的前置設定
# substr(-8, -1) 取最後 8 個字元，確保唯一性

resource "aws_cognito_user_pool_domain" "main" {
  # TODO
}
