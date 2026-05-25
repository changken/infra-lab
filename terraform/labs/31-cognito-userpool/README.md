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
  --temporary-password "Temp@.1234" \
  --message-action "SUPPRESS"
```

`--message-action SUPPRESS` 避免 Cognito 嘗試寄驗證信（lab 環境不需要）。

**期望輸出**：`User.UserStatus` 為 `FORCE_CHANGE_PASSWORD`

### 3. 設定永久密碼（跳過 FORCE_CHANGE_PASSWORD）

```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id "$USER_POOL_ID" \
  --username "testuser@example.com" \
  --password "Test@.1234" \
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
  --auth-parameters USERNAME="testuser@example.com",PASSWORD="Test@.1234")

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
| `InvalidParameterException: Domain cannot contain reserved word` | `var.project` 包含保留字（cognito / aws / amazon 等），改用 `auth-lab` 這類不含保留字的名稱 |
| `terraform validate` 失敗 | 正常：resource body 還是 `# TODO`，填完所有欄位後再執行 |
| base64 decode 出現亂碼 | JWT 用 base64url（`-` 和 `_`），需補 `=` padding，驗證腳本已處理 |
| `UserNotFoundException` | 用戶建立失敗，確認 `--user-pool-id` 正確，或重新執行 `admin-create-user` |
