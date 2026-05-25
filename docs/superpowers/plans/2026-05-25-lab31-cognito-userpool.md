# Lab 31: Cognito User Pool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `terraform/labs/31-cognito-userpool/` 的填空式 lab 骨架，包含 3 個 TODO 資源（User Pool、App Client、User Pool Domain）、完整 README，以及純 CLI 驗證流程。

**Architecture:** 3 個 Terraform 資源（aws_cognito_user_pool、aws_cognito_user_pool_client、aws_cognito_user_pool_domain），resource body 保持空白（`# TODO`），詳細提示寫在 comment block 上方，供使用者自行填寫。

**Tech Stack:** Terraform >= 1.0, AWS Provider ~> 5.0, Cognito

---

## 檔案對應表

| 檔案 | 動作 | 說明 |
|------|------|------|
| `terraform/labs/31-cognito-userpool/terraform.tf` | 建立 | Provider 設定 |
| `terraform/labs/31-cognito-userpool/variables.tf` | 建立 | 輸入變數 |
| `terraform/labs/31-cognito-userpool/locals.tf` | 建立 | common_tags |
| `terraform/labs/31-cognito-userpool/.gitignore` | 建立 | 排除 tfstate、.terraform/、*.tfvars |
| `terraform/labs/31-cognito-userpool/terraform.tfvars.example` | 建立 | 範例值 |
| `terraform/labs/31-cognito-userpool/main.tf` | 建立 | 3 個 TODO 資源骨架 |
| `terraform/labs/31-cognito-userpool/outputs.tf` | 建立 | 6 個輸出值 |
| `terraform/labs/31-cognito-userpool/README.md` | 建立 | Lab 指南（含完整驗證腳本）|
| `terraform/labs/31-cognito-userpool/.terraform.lock.hcl` | 產生 | `terraform init` 後提交 |

---

## Task 1：建立基礎設定檔

**Files:**
- Create: `terraform/labs/31-cognito-userpool/terraform.tf`
- Create: `terraform/labs/31-cognito-userpool/variables.tf`
- Create: `terraform/labs/31-cognito-userpool/locals.tf`
- Create: `terraform/labs/31-cognito-userpool/.gitignore`
- Create: `terraform/labs/31-cognito-userpool/terraform.tfvars.example`

- [ ] **Step 1: 建立 terraform.tf**

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}
```

- [ ] **Step 2: 建立 variables.tf**

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "cognito-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
```

- [ ] **Step 3: 建立 locals.tf**

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "31-cognito-userpool"
    ManagedBy   = "terraform"
  }
}
```

- [ ] **Step 4: 建立 .gitignore**

```
# Terraform state
*.tfstate
*.tfstate.*
.terraform/
*.tfvars
!*.tfvars.example

# Sensitive
*.pem
*.key
```

- [ ] **Step 5: 建立 terraform.tfvars.example**

```hcl
region      = "us-east-1"
project     = "cognito-lab"
environment = "dev"
```

- [ ] **Step 6: Commit**

```bash
git add terraform/labs/31-cognito-userpool/terraform.tf \
        terraform/labs/31-cognito-userpool/variables.tf \
        terraform/labs/31-cognito-userpool/locals.tf \
        terraform/labs/31-cognito-userpool/.gitignore \
        terraform/labs/31-cognito-userpool/terraform.tfvars.example
git commit -m "feat(labs): add lab 31 base config files"
```

---

## Task 2：建立 main.tf（填空式骨架）

**Files:**
- Create: `terraform/labs/31-cognito-userpool/main.tf`

- [ ] **Step 1: 建立 main.tf**

```hcl
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
```

- [ ] **Step 2: 驗證格式**

```bash
cd terraform/labs/31-cognito-userpool
terraform fmt -check
```

Expected: 無輸出（格式正確），或輸出 `main.tf`（有格式問題則執行 `terraform fmt` 修正）

- [ ] **Step 3: Commit**

```bash
git add terraform/labs/31-cognito-userpool/main.tf
git commit -m "feat(labs): add lab 31 main.tf with TODO scaffolds"
```

---

## Task 3：建立 outputs.tf

**Files:**
- Create: `terraform/labs/31-cognito-userpool/outputs.tf`

- [ ] **Step 1: 建立 outputs.tf**

```hcl
output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.main.arn
}

output "app_client_id" {
  description = "Cognito App Client ID（initiate-auth 的 --client-id 參數）"
  value       = aws_cognito_user_pool_client.app.id
}

output "user_pool_domain" {
  description = "Cognito Hosted UI domain prefix"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "user_pool_endpoint" {
  description = "User Pool OIDC Endpoint（JWKS 驗證基礎 URL）"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "jwks_uri" {
  description = "JWT 公鑰端點（API 服務驗證 token 簽名時使用）"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
}
```

- [ ] **Step 2: Commit**

```bash
git add terraform/labs/31-cognito-userpool/outputs.tf
git commit -m "feat(labs): add lab 31 outputs.tf"
```

---

## Task 4：建立 README.md

**Files:**
- Create: `terraform/labs/31-cognito-userpool/README.md`

- [ ] **Step 1: 建立 README.md**

```markdown
# Lab 31: Cognito User Pool + App Client + JWT 驗證

> 建立 Cognito User Pool，透過 AWS CLI 完成完整認證流程，親眼解析 JWT 結構與三種 Token 的差異。

**費用等級**：🟢 安全（$0，Cognito 免費額度 50,000 MAU/月）

---

## 學習目標

- 理解 Cognito **User Pool** vs **Identity Pool** 的差異與使用場景
- 設定 User Pool 的密碼政策與 email 自動驗證屬性
- 設定 App Client 的 `explicit_auth_flows` 與 `generate_secret = false` 的原因
- 透過 `initiate-auth` 取得 JWT，解析 **ID Token / Access Token / Refresh Token** 三者差異
- 理解 JWT 三段結構（`header.payload.signature`）與 base64url 編碼

---

## 架構

```
AWS Cognito
  └── User Pool（${var.project}-pool）
        │  username_attributes: email
        │  password_policy: 8+ 位，大小寫 + 數字 + 符號
        │  auto_verified_attributes: email
        │
        ├── App Client（${var.project}-client）
        │     generate_secret = false（CLI/SPA 不能儲存 secret）
        │     auth flows: USER_PASSWORD_AUTH, REFRESH_TOKEN_AUTH
        │
        └── User Pool Domain（${var.project}-<acct-suffix>）
              Hosted UI 前綴（Lab 40 整合 API GW Authorizer 時使用）
              URL: https://<domain>.auth.<region>.amazoncognito.com
```

---

## 你要做的事

| TODO | 資源 | 關鍵設定 |
|------|------|---------|
| 1 | `aws_cognito_user_pool` | `name`、`username_attributes`、`password_policy`、`auto_verified_attributes`、`admin_create_user_config` |
| 2 | `aws_cognito_user_pool_client` | `user_pool_id`、`generate_secret = false`、`explicit_auth_flows`、token 有效期 |
| 3 | `aws_cognito_user_pool_domain` | `domain`（`${var.project}-${substr(account_id, -8, -1)}`）、`user_pool_id` |

---

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate   # 填完所有 TODO 後再執行
terraform plan
terraform apply
```

> **注意**：resource body 空白時 `terraform validate` 會失敗，這是正常的。
> 填完所有 `# TODO` 內容後再執行 validate。

---

## 驗證

### 1. 取得輸出值

```bash
USER_POOL_ID=$(terraform output -raw user_pool_id)
CLIENT_ID=$(terraform output -raw app_client_id)

echo "User Pool ID : $USER_POOL_ID"
echo "App Client ID: $CLIENT_ID"
```

### 2. 建立測試用戶

```bash
aws cognito-idp admin-create-user \
  --user-pool-id "$USER_POOL_ID" \
  --username "testuser@example.com" \
  --temporary-password "Temp@1234!" \
  --message-action SUPPRESS
```

`--message-action SUPPRESS` 避免 Cognito 嘗試寄驗證信（lab 環境不需要）。

**期望輸出**：`User.UserStatus` 為 `FORCE_CHANGE_PASSWORD`

### 3. 設定永久密碼（跳過 FORCE_CHANGE_PASSWORD）

```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id "$USER_POOL_ID" \
  --username "testuser@example.com" \
  --password "Test@1234!" \
  --permanent
```

> 為什麼需要這步？
> 新建用戶狀態為 `FORCE_CHANGE_PASSWORD`，執行 `initiate-auth` 時
> 會回傳 `NEW_PASSWORD_REQUIRED` challenge 而非 token。
> 加 `--permanent` 直接將狀態切為 `CONFIRMED`。

驗證狀態已變更：

```bash
aws cognito-idp admin-get-user \
  --user-pool-id "$USER_POOL_ID" \
  --username "testuser@example.com" \
  --query 'UserStatus'
# 期望輸出："CONFIRMED"
```

### 4. 取得 JWT Token

```bash
TOKENS=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id "$CLIENT_ID" \
  --auth-parameters USERNAME="testuser@example.com",PASSWORD="Test@1234!")

echo "$TOKENS" | python3 -m json.tool
```

**期望輸出（節錄）**：
```json
{
    "AuthenticationResult": {
        "AccessToken": "eyJra...",
        "ExpiresIn": 3600,
        "TokenType": "Bearer",
        "RefreshToken": "eyJjd...",
        "IdToken": "eyJra..."
    }
}
```

### 5. 解析 ID Token Payload

```bash
ID_TOKEN=$(echo "$TOKENS" | python3 -c "
import json, sys
print(json.load(sys.stdin)['AuthenticationResult']['IdToken'])
")

echo "$ID_TOKEN" | cut -d. -f2 | python3 -c "
import sys, base64, json
payload = sys.stdin.read().strip()
padding = 4 - len(payload) % 4
decoded = base64.urlsafe_b64decode(payload + '=' * padding)
print(json.dumps(json.loads(decoded), indent=2))
"
```

**期望輸出**：
```json
{
  "sub": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "email_verified": true,
  "iss": "https://cognito-idp.us-east-1.amazonaws.com/<USER_POOL_ID>",
  "cognito:username": "testuser@example.com",
  "aud": "<APP_CLIENT_ID>",
  "token_use": "id",
  "auth_time": 1716600000,
  "exp": 1716603600,
  "email": "testuser@example.com"
}
```

注意 `"token_use": "id"` → 這是 **ID Token**，包含 email 等用戶屬性。

### 6. 解析 Access Token（比較差異）

```bash
ACCESS_TOKEN=$(echo "$TOKENS" | python3 -c "
import json, sys
print(json.load(sys.stdin)['AuthenticationResult']['AccessToken'])
")

echo "$ACCESS_TOKEN" | cut -d. -f2 | python3 -c "
import sys, base64, json
payload = sys.stdin.read().strip()
padding = 4 - len(payload) % 4
decoded = base64.urlsafe_b64decode(payload + '=' * padding)
print(json.dumps(json.loads(decoded), indent=2))
"
```

觀察 Access Token 的 `"token_use": "access"` 且**不包含 email 等用戶屬性** — 這是 ID Token 和 Access Token 最核心的差異。

### 7. 查看 JWKS 公鑰端點

```bash
JWKS_URI=$(terraform output -raw jwks_uri)
curl -s "$JWKS_URI" | python3 -m json.tool
```

這個端點是 API Gateway 或自建服務驗證 JWT 簽名時使用的公鑰來源（RS256 非對稱加密）。

---

## 結束

```bash
terraform destroy -auto-approve
```

確認輸出包含 `Destroy complete!`，Cognito User Pool 一旦刪除無法恢復。

---

## 成本估算

| 資源 | 費用 |
|------|------|
| Cognito User Pool | $0（前 50,000 MAU/月免費）|
| Cognito App Client | $0 |
| Cognito User Pool Domain | $0 |
| **合計** | **$0** |

---

## 核心概念釐清

### User Pool vs Identity Pool

| | User Pool | Identity Pool |
|--|-----------|---------------|
| 功能 | 使用者帳號管理、JWT 發行 | 將 JWT / 第三方 token 換成 AWS 臨時憑證 |
| 回傳 | ID Token / Access Token / Refresh Token | AWS Access Key + Secret Key + Session Token |
| 使用場景 | 向你的 API 驗證「我是誰」| 讓使用者直接存取 S3 / DynamoDB |
| Lab 對應 | **本 lab（Lab 31）** | 通常搭配 User Pool（Lab 40 延伸）|

### JWT 三種 Token 差異

| Token | 包含內容 | 有效期（預設）| 用途 |
|-------|---------|-------------|------|
| **ID Token** | email, sub, name 等用戶屬性 | 60 分鐘 | 向你的 API 確認「我是誰」|
| **Access Token** | OAuth2 scope, username | 60 分鐘 | 向 API Gateway Authorizer 授權 |
| **Refresh Token** | 換取新 token 的憑證 | 30 天 | 背景自動更新，不傳給 API |

### generate_secret 選擇

| 場景 | 設定 | 原因 |
|------|------|------|
| SPA（React / Vue）| `false` | 前端程式碼可被用戶看到，不能儲存 secret |
| Mobile App | `false` | App 可被反組譯，不能硬編碼 secret |
| CLI 工具 | `false` | 同上，binary 可被分析 |
| Server-side Web App | `true` | Secret 儲存在伺服器，使用者看不到 |

### `--permanent` 旗標的必要性

```
新建用戶狀態：FORCE_CHANGE_PASSWORD
    │
    ├── initiate-auth → 回傳 NEW_PASSWORD_REQUIRED challenge（沒有 token）
    │
    └── admin-set-user-password --permanent → 狀態變 CONFIRMED
            │
            └── initiate-auth → 回傳 AuthenticationResult（有 token）✅
```

---

## 取捨決策（面試常考）

| 情境 | 選擇 | 原因 |
|------|------|------|
| 需要管理使用者帳號密碼 | Cognito User Pool | 不要自己實作 JWT，讓 AWS 管 |
| 第三方 OAuth 登入 | Cognito + Identity Provider | 可整合 Google / Facebook / Apple |
| 需要 AWS 臨時憑證 | Cognito Identity Pool | User Pool 給 JWT，Identity Pool 給 AWS credentials |
| API 認證 | Cognito + API Gateway Authorizer | Lab 40 主題，Authorizer 自動驗證 JWT |

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `NotAuthorizedException: Incorrect username or password` | 密碼不符合密碼政策，或用戶狀態仍是 `FORCE_CHANGE_PASSWORD`（忘記加 `--permanent`）|
| `InvalidParameterException: USER_PASSWORD_AUTH flow not enabled` | App Client 的 `explicit_auth_flows` 未加 `ALLOW_USER_PASSWORD_AUTH` |
| `InitiateAuth failed: MISSING_REQUIRED_AUTH_FLOW` | `explicit_auth_flows` 缺少 `ALLOW_REFRESH_TOKEN_AUTH` |
| `DomainAlreadyExists` | Domain prefix 全域衝突，確認 `substr(account_id, -8, -1)` 已加入，或換一個 project 名稱 |
| `terraform validate` 失敗 | 正常：resource body 還是 `# TODO`，填完所有欄位後再執行 |
| base64 decode 出現亂碼 | JWT 用 base64url（`-` 和 `_`），需補 `=` padding，驗證腳本已處理 |
| `UserNotFoundException` | 用戶建立失敗，確認 `--user-pool-id` 正確，或重新執行 `admin-create-user` |
```

- [ ] **Step 2: Commit**

```bash
git add terraform/labs/31-cognito-userpool/README.md
git commit -m "docs(labs): add lab 31 README with verification guide"
```

---

## Task 5：terraform init + terraform fmt + 提交 lock file

**Files:**
- Generate: `terraform/labs/31-cognito-userpool/.terraform.lock.hcl`

- [ ] **Step 1: 執行 terraform init**

```bash
cd terraform/labs/31-cognito-userpool
terraform init
```

Expected output（節錄）：
```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

- [ ] **Step 2: 執行 terraform fmt（確認格式整潔）**

```bash
terraform fmt
```

Expected: 無輸出（格式已正確），或列出已修正的檔案。

- [ ] **Step 3: 提交 lock file**

`.terraform.lock.hcl` 需要進入版本控制，鎖定 Provider 版本。

```bash
cd ../../../   # 回到 repo root
git add terraform/labs/31-cognito-userpool/.terraform.lock.hcl
git commit -m "chore(labs): add lab 31 terraform lock file"
```

---

## Task 6：更新 roadmap-v2.md（標記 lab 31 進行中）

**Files:**
- Modify: `terraform/docs/roadmap-v2.md`

- [ ] **Step 1: 確認 roadmap 中 lab 31 的現有狀態**

開啟 `terraform/docs/roadmap-v2.md`，找到 Phase 1-C 表格中的這一行：

```markdown
| 31 | `31-cognito-userpool` | Cognito User Pool + App Client + JWT 驗證 | $0 | DVA |
```

- [ ] **Step 2: 更新為「進行中」標記（骨架已建立）**

將該行更新為：

```markdown
| 31 🚧 | `31-cognito-userpool` | Cognito User Pool + App Client + JWT 驗證 | $0 | DVA |
```

- [ ] **Step 3: Commit**

```bash
git add terraform/docs/roadmap-v2.md
git commit -m "docs(roadmap): mark lab 31 as scaffolded"
```

---

## 自我審查清單

完成所有 Task 後確認：

- [ ] `terraform/labs/31-cognito-userpool/` 目錄存在且包含所有 8 個檔案 + lock file
- [ ] `main.tf` 的 3 個 resource blocks 均為空 body（只有 `# TODO`）
- [ ] `outputs.tf` 中 6 個 output 的 `value` 引用了正確的 resource 屬性
- [ ] README 的驗證指令可以 copy-paste 執行（無 placeholder）
- [ ] `.gitignore` 包含 `.terraform/` 但不包含 `.terraform.lock.hcl`
- [ ] `terraform fmt -check` 無報錯
