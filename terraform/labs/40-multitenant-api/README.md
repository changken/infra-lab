# Lab 40：多租戶 SaaS API

> **場景**：建立一個 SaaS 後端，不同租戶透過 JWT 身份隔離，各自只能存取自己的資料。  
> **費用等級**：🟢 安全（$0，Cognito 前 50,000 MAU 免費，Lambda / DynamoDB / API GW 均在免費額度）

---

## 學習目標

完成本 lab 後，你能夠：

- 建立 Cognito User Pool 並新增自訂屬性（`custom:tenant_id`），將租戶身份嵌入 JWT
- 設定 API Gateway HTTP API 的 **JWT Authorizer**，讓 API GW 自動驗簽，無需額外 Lambda
- 理解 JWT Authorizer 的 `issuer` / `audience` 格式，以及為何 REST API Authorizer 設定不同
- 實作 **DynamoDB 單表多租戶隔離**：`pk = "TENANT#{tenant_id}"` 讓 Query 自然隔離資料
- 在 Lambda 中從 `event["requestContext"]["authorizer"]["jwt"]["claims"]` 讀取 tenant_id

---

## 架構

```
用戶 A（tenant-A）                    用戶 B（tenant-B）
     │                                      │
     │ POST /items  Bearer <JWT-A>           │ POST /items  Bearer <JWT-B>
     ▼                                      ▼
┌──────────────────────────────────────────────────────┐
│             API Gateway HTTP API                      │
│                                                       │
│  JWT Authorizer（Cognito）                            │
│  ├─ 驗證 token 簽章（JWKS 公鑰）                     │
│  ├─ 驗證 aud = App Client ID                         │
│  └─ 注入 claims 到 requestContext                    │
└──────────────────────────────────────────────────────┘
     │ event.requestContext.authorizer.jwt.claims
     ▼
Lambda: api
  ├─ tenant_id = claims["custom:tenant_id"]
  ├─ GET /items  → DynamoDB Query pk="TENANT#tenant-A"
  └─ POST /items → DynamoDB PutItem pk="TENANT#tenant-A", sk="ITEM#uuid"
                                            │
                              ┌─────────────▼────────────┐
                              │         DynamoDB          │
                              │  pk="TENANT#tenant-A"    │ ← 用戶 A 的資料
                              │  pk="TENANT#tenant-B"    │ ← 用戶 B 的資料（完全隔離）
                              └──────────────────────────┘
```

### DynamoDB 單表 Key 設計

```
pk (Partition Key)     sk (Sort Key)           其他欄位
──────────────────     ─────────────────       ──────────────
TENANT#tenant-A        ITEM#uuid-1             name, data, created_at
TENANT#tenant-A        ITEM#uuid-2             name, data, created_at
TENANT#tenant-B        ITEM#uuid-3             name, data, created_at  ← 不同分區，完全隔離
```

---

## 你要做的事

| TODO | 資源 | 關鍵設定 |
|------|------|---------|
| 1 | Cognito User Pool + App Client | `schema` 自訂 `tenant_id` 屬性，`explicit_auth_flows` |
| 2 | DynamoDB Table | `hash_key = "pk"`, `range_key = "sk"`，PAY_PER_REQUEST |
| 3 | Lambda IAM Role + Policy | 只允許 `dynamodb:Query` + `dynamodb:PutItem` |
| 4 | Lambda Function | `TABLE_NAME` 環境變數 |
| 5 | API GW HTTP API + JWT Authorizer | `issuer` 格式 + `audience = [client_id]` |
| 6 | Integration + Routes + Stage + Permission | `payload_format_version = "2.0"`, `authorization_type = "JWT"` |

---

## 指令

```bash
# 1. 複製 tfvars
cp terraform.tfvars.example terraform.tfvars

# 2. 初始化
terraform init

# 3. 格式化
terraform fmt

# 4. 驗證
terraform validate

# 5. 預覽
terraform plan

# 6. 部署
terraform apply -auto-approve
```

---

## 驗證方式

### 步驟 1：取得部署輸出

```bash
USER_POOL_ID=$(terraform output -raw user_pool_id)
CLIENT_ID=$(terraform output -raw user_pool_client_id)
API=$(terraform output -raw api_endpoint)
TABLE=$(terraform output -raw dynamodb_table_name)
```

### 步驟 2：建立兩個不同租戶的用戶

```bash
# 建立 Tenant A 用戶
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username user-a@example.com \
  --user-attributes \
    Name=email,Value=user-a@example.com \
    Name=custom:tenant_id,Value=tenant-A \
  --temporary-password TempPass123! \
  --message-action SUPPRESS

# 建立 Tenant B 用戶
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username user-b@example.com \
  --user-attributes \
    Name=email,Value=user-b@example.com \
    Name=custom:tenant_id,Value=tenant-B \
  --temporary-password TempPass123! \
  --message-action SUPPRESS

# 設定永久密碼（跳過 NEW_PASSWORD_REQUIRED 挑戰）
aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username user-a@example.com \
  --password MyPassword123! --permanent

aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username user-b@example.com \
  --password MyPassword123! --permanent
```

### 步驟 3：取得 JWT Token

```bash
# 取得 Tenant A 的 IdToken
TOKEN_A=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $CLIENT_ID \
  --auth-parameters USERNAME=user-a@example.com,PASSWORD=MyPassword123! \
  --query 'AuthenticationResult.IdToken' --output text)

# 取得 Tenant B 的 IdToken
TOKEN_B=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $CLIENT_ID \
  --auth-parameters USERNAME=user-b@example.com,PASSWORD=MyPassword123! \
  --query 'AuthenticationResult.IdToken' --output text)

echo "Token A: ${TOKEN_A:0:50}..."
```

### 步驟 4：用兩個租戶各自新增資料

```bash
# Tenant A 新增兩筆資料
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d '{"name":"product-A1","data":{"price":100}}' \
  $API/items | jq .

curl -s -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d '{"name":"product-A2","data":{"price":200}}' \
  $API/items | jq .

# Tenant B 新增一筆資料
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN_B" \
  -H "Content-Type: application/json" \
  -d '{"name":"product-B1","data":{"price":300}}' \
  $API/items | jq .
```

### 步驟 5：確認租戶隔離（關鍵測試）

```bash
# Tenant A 只能看到自己的 2 筆資料
echo "=== Tenant A 的資料 ==="
curl -s -H "Authorization: Bearer $TOKEN_A" $API/items | jq '.count, .items[].name'

# Tenant B 只能看到自己的 1 筆資料
echo "=== Tenant B 的資料 ==="
curl -s -H "Authorization: Bearer $TOKEN_B" $API/items | jq '.count, .items[].name'

# 預期：Tenant A 看到 count=2，Tenant B 看到 count=1，互不干擾
```

### 步驟 6：DynamoDB 直接驗證 Key 隔離

```bash
# 查詢 Tenant A 在 DynamoDB 的 partition
aws dynamodb query \
  --table-name $TABLE \
  --key-condition-expression 'pk = :pk' \
  --expression-attribute-values '{":pk":{"S":"TENANT#tenant-A"}}' \
  --query 'Items[*].{pk:pk.S,sk:sk.S,name:name.S}'

# 確認 Tenant A 的資料的 pk 前綴都是 "TENANT#tenant-A"
```

### 步驟 7：確認無效 Token 被拒（JWT Authorizer 效果）

```bash
# 不帶 token 呼叫（預期 401）
curl -s -o /dev/null -w "%{http_code}" $API/items

# 帶無效 token（預期 401）
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer invalid.token.here" \
  $API/items
```

---

## 結束

```bash
terraform destroy -auto-approve
```

> **注意**：Cognito User Pool 中的用戶資料會隨 `destroy` 一起刪除。如果有重要測試帳號，先 export。

---

## 成本估算

| 資源 | 計費模式 | 預估費用 |
|------|---------|---------|
| Cognito User Pool | 前 50,000 MAU 免費 | $0.00 |
| API Gateway HTTP API | 前 1M requests/月免費 | $0.00 |
| Lambda | 前 1M 次免費，128MB | $0.00 |
| DynamoDB | PAY_PER_REQUEST，前 25GB 免費 | $0.00 |
| **合計** | | **$0.00** |

---

## 架構決策紀錄（ADR）

### ADR-1：為什麼用 JWT Authorizer 而不是 Lambda Authorizer？

**決策**：API GW HTTP API 使用內建 JWT Authorizer（`authorizer_type = "JWT"`），而非自訂 Lambda Authorizer。

**理由**：
- **零 Lambda 成本**：JWT Authorizer 由 API GW 原生執行，不需要額外 Lambda Function，無冷啟動延遲。
- **設定簡單**：只需提供 Cognito 的 `issuer` URL 和 `audience`，API GW 自動從 JWKS 端點取得公鑰驗簽。
- **可靠性高**：驗簽邏輯由 AWS 管理，不需要維護自訂 token 驗證程式碼。

**Lambda Authorizer 的適用場景**：
- token 格式不是標準 JWT（如 API Key、自訂 HMAC token）
- 需要驗簽之外的額外邏輯（如查詢資料庫確認用戶是否被封鎖）
- 需要在 Lambda 中豐富化請求 context（如添加 user role、permission 等）

**結論**：使用 Cognito 作為 IdP 時，優先用 JWT Authorizer；有複雜自訂邏輯時才用 Lambda Authorizer。

---

### ADR-2：為什麼用 DynamoDB 單表多租戶設計？

**決策**：所有租戶資料存在同一張 DynamoDB 表，以 `pk = "TENANT#{tenant_id}"` 作邏輯隔離。

**理由**：
- **成本效益**：PAY_PER_REQUEST 模式下，單表不需要為每個租戶的「靜默時段」付出最低費用。若每個租戶一張表，100 個租戶就有 100 張表的 overhead。
- **管理簡單**：Terraform 只需管理 1 個 `aws_dynamodb_table` 資源，不需要動態建立/刪除表。
- **自然隔離**：DynamoDB 的 `Query` 只在同一個 Partition Key 內搜尋，`pk = "TENANT#tenant-A"` 的查詢永遠不會返回 `pk = "TENANT#tenant-B"` 的資料，無需額外過濾邏輯。

**代價**：
- 若需要「不同租戶用不同 KMS 加密金鑰」，單表無法實現（需要 per-tenant 表）。
- 若租戶資料量差異極大，熱分區（hot partition）可能影響高流量租戶。

**結論**：< 1000 個租戶、無嚴格數據主權要求時，單表設計最佳；enterprise 級別或合規要求嚴格時，考慮 per-tenant 表。

---

### ADR-3：為什麼用 `custom:tenant_id` 而不是從外部資料庫查詢？

**決策**：租戶 ID 作為自訂屬性存在 Cognito User Pool（`custom:tenant_id`），並在 JWT IdToken 中以 claim 形式傳遞。

**理由**：
- **零額外查詢**：Lambda 直接從 JWT claims 讀取 `custom:tenant_id`，不需要查詢「用戶-租戶對應表」，節省 1 次 DynamoDB 呼叫（通常 1-5ms）。
- **可靠性**：JWT 是不可偽造的（由 Cognito 簽章），Lambda 可以完全信任 claims 中的 tenant_id。
- **無狀態設計**：Lambda 不需要維護 session 或快取，每個請求都是自包含的（self-contained）。

**代價**：
- 若用戶的租戶歸屬需要變更，必須更新 Cognito User Pool 中的 `custom:tenant_id` 屬性，且舊 token 在過期前仍有效（IdToken 預設 1 小時）。
- 租戶 ID 存在 JWT 中，任何能解碼 JWT 的人都能看到（JWT 只驗簽，不加密）。

**結論**：對於租戶歸屬固定（用戶加入後不切換租戶）的場景，Cognito custom attribute 是最簡單可靠的方式。

---

## 可觀測性設計

| 觀測點 | 工具 | 查詢方式 |
|--------|------|---------|
| API 請求成功/失敗 | API GW Access Log | 需手動設定 `access_log_settings`（此 lab 省略）|
| Lambda 執行錯誤 | CloudWatch Logs | `aws logs tail /aws/lambda/saas-lab-api` |
| JWT 驗證失敗（401）| CloudWatch Metrics | API GW `4XXError` metric |
| DynamoDB 讀寫延遲 | CloudWatch Metrics | `SuccessfulRequestLatency` in `AWS/DynamoDB` |
| 租戶流量分布 | CloudWatch Logs Insights | 過濾 `[REQUEST]` log 行，group by tenant_id |

**CloudWatch Logs Insights 範例**（查詢各租戶請求數）：

```sql
fields @timestamp, @message
| filter @message like /\[REQUEST\]/
| parse @message "[REQUEST] * * tenant=*" as method, path, tenant
| stats count() as requests by tenant
| sort requests desc
```

---

## 卡關提示

| 症狀 | 原因 | 解法 |
|------|------|------|
| API 回傳 401 | JWT Authorizer 驗簽失敗 | 確認 `issuer` 格式正確（region 和 user_pool_id 對應）；確認 `audience` = App Client ID |
| API 回傳 403 | Route 設定了 Authorizer 但未包含 | 確認 route 的 `authorizer_id` 指向正確 authorizer |
| `initiate-auth` 失敗 | App Client 未啟用 `ALLOW_USER_PASSWORD_AUTH` | 在 `explicit_auth_flows` 加入此值 |
| Lambda 讀不到 `custom:tenant_id` | App Client 的 `read_attributes` 未包含 `custom:tenant_id` | 加入 `read_attributes = ["email", "custom:tenant_id"]` |
| `custom:tenant_id` 在 JWT claims 中出現 `null` | 建立用戶時未設定此屬性 | 確認 `admin-create-user` 的 `--user-attributes` 含 `Name=custom:tenant_id,Value=xxx` |
| DynamoDB Query 回傳空列表 | Lambda 讀到的 tenant_id 和建立資料時不同 | 用 `aws logs tail` 確認 Lambda log 中的 `tenant=` 值是否一致 |
| `payload_format_version` 問題 | Lambda 收到的 `event.requestContext` 結構與預期不符 | HTTP API 必須設 `payload_format_version = "2.0"`，否則 claims 注入路徑不同 |
| Terraform plan 報 schema 格式錯誤 | `schema` 的 `name` 不能含 `custom:` 前綴 | schema 裡用 `name = "tenant_id"`，不是 `name = "custom:tenant_id"` |

---

## 面試故事

> 「我在 Lab 40 實作了一個多租戶 SaaS API。架構是 Cognito → API Gateway JWT Authorizer → Lambda → DynamoDB。
>
> Cognito User Pool 的每個用戶有 `custom:tenant_id` 自訂屬性，登入後 IdToken 就包含這個 claim。API GW 的 JWT Authorizer 自動驗簽，不需要額外的 Lambda，驗完把 claims 注入給後端 Lambda。
>
> DynamoDB 用單表多租戶設計，partition key 是 `TENANT#{tenant_id}`。因為 DynamoDB 的 Query 只在同一個分區內查找，租戶 A 的請求永遠看不到租戶 B 的資料，完全不需要在應用層加過濾條件。
>
> 和每個租戶一張表相比，單表設計在 PAY_PER_REQUEST 模式下成本更低，Terraform 也只需要管一個資源。代價是如果需要 per-tenant 的 KMS 加密金鑰，就必須改成多表設計。」

---

*建立於 2026-05-28*
