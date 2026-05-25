# Lab 31: Cognito User Pool + App Client + JWT 驗證 — 設計文件

**日期**: 2026-05-25
**路徑**: `terraform/labs/31-cognito-userpool/`
**費用**: $0（Cognito 免費額度 50,000 MAU/月）
**認證覆蓋**: DVA

---

## 目標

建立一個可運作的 Cognito User Pool，讓使用者透過 CLI 完成完整認證流程，並親眼看到 JWT 的結構與內容。

---

## 架構

```
AWS Cognito
  └── User Pool（email 作為 username）
        ├── 密碼政策（8 位以上，含大小寫/數字/符號）
        ├── email 自動驗證屬性
        ├── App Client（USER_PASSWORD_AUTH，無 client secret）
        └── User Pool Domain（domain prefix，供 Hosted UI 使用）
```

---

## 資源（TODOs）

| # | 資源 | 關鍵設定 |
|---|------|---------|
| 1 | `aws_cognito_user_pool` | `username_attributes = ["email"]`、密碼政策、`auto_verified_attributes = ["email"]` |
| 2 | `aws_cognito_user_pool_client` | `explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]`、`generate_secret = false` |
| 3 | `aws_cognito_user_pool_domain` | `domain = "${var.project}-auth-<suffix>"` |

---

## 檔案結構

```
31-cognito-userpool/
├── terraform.tf            # provider aws ~> 5.0，無額外 provider
├── variables.tf            # region, project, environment
├── locals.tf               # common_tags
├── main.tf                 # 3 個 TODO 資源
├── outputs.tf              # user_pool_id, app_client_id, user_pool_domain, user_pool_endpoint
├── terraform.tfvars.example
├── .gitignore
└── README.md
```

---

## 驗證流程（純 CLI）

1. `terraform apply`
2. 建立測試用戶：`aws cognito-idp admin-create-user`
3. 設定永久密碼：`aws cognito-idp admin-set-user-password --permanent`
4. 取得 JWT：`aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH`
5. 解析 ID Token payload：`echo '<token>' | cut -d. -f2 | base64 -d | python3 -m json.tool`
6. 區分 ID Token / Access Token / Refresh Token
7. `terraform destroy`

---

## 核心概念（README 必須涵蓋）

- User Pool vs Identity Pool 差異
- `generate_secret = false` 的適用場景（SPA、Mobile CLI）
- JWT 三段結構（header.payload.signature）
- ID Token vs Access Token vs Refresh Token 用途差異
- `admin-set-user-password --permanent` 為何要加（跳過 FORCE_CHANGE_PASSWORD 狀態）

---

## main.tf TODO 格式規範

遵循現有 lab 慣例：
- 每個 TODO 上方有詳細 comment block（資源說明、文件連結、需要設定的欄位）
- `resource "xxx" "yyy" { # TODO }` 本體保持空白供使用者填寫

---

## 面試重點（README 卡關提示旁邊補充）

| 情境 | 選擇 | 原因 |
|------|------|------|
| 需要儲存使用者帳號密碼 | Cognito User Pool | 不要自己實作，讓 AWS 管 |
| 第三方 OAuth 登入 | Cognito Identity Provider | 整合 Google/Facebook |
| 臨時 AWS 憑證 | Cognito Identity Pool | User Pool 給你 JWT，Identity Pool 給你 AWS credentials |
| API 認證 | Cognito + API Gateway Authorizer | Lab 40 主題 |
