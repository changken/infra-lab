# Lab 08: Lambda + DynamoDB CRUD API

把 Lab 05（DynamoDB）、06（Lambda）、07（API Gateway）組合起來，
建立一個完整的 Serverless CRUD API。

## 學習目標

- `aws_iam_role_policy`：自訂最小權限（vs 內建 Policy）
- `TABLE_NAME` 環境變數：Lambda 讀 DynamoDB table 名稱的正確做法
- path parameter：`GET /items/{item_id}` 的路由設計
- 多個 route 共用同一個 integration
- 如何用 curl 測試 REST API

## 架構

```
curl
  → API Gateway HTTP API
      → Lambda（crud.handler）
          → DynamoDB table（items）

API 路由：
  GET    /items           → 列出全部
  GET    /items/{item_id} → 取得單筆
  POST   /items           → 新增（回傳 UUID）
  DELETE /items/{item_id} → 刪除
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_iam_role_policy` | 自訂 DynamoDB 權限（鎖定到特定 table ARN）|
| 2 | `aws_lambda_function` | 新增 TABLE_NAME 環境變數 |
| 3 | `aws_apigatewayv2_api` + `stage` | 複習 Lab 07 |
| 4 | Integration + 4 Routes + Permission | 多條路由共用一個 integration |

再補完 `outputs.tf` 的 1 個 TODO（test_commands）。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：11 to add
terraform apply
```

**預期 plan：11 個 to add**
（DynamoDB + IAM Role + Basic Policy + DynamoDB Policy +
 Lambda + API + Stage + Integration + 4 Routes + Permission）

### 驗證流程

```bash
BASE=$(terraform output -raw api_endpoint)

# 1. 新增一筆
curl -X POST "$BASE/items" \
  -H "Content-Type: application/json" \
  -d '{"name": "book", "description": "terraform guide"}'
# 記下回傳的 item_id

# 2. 列出全部
curl "$BASE/items"

# 3. 取得單筆（替換 {id}）
curl "$BASE/items/{id}"

# 4. 刪除
curl -X DELETE "$BASE/items/{id}"

# 5. 再 GET 確認已刪除（應回 404）
curl "$BASE/items/{id}"
```

### 結束

```bash
terraform destroy -auto-approve
```

## 成本

**< $0.50**。DynamoDB PAY_PER_REQUEST + Lambda + API Gateway 在 Free Tier 範圍內。
少量測試呼叫幾乎 $0。

## 關鍵學習：最小權限原則

```hcl
# ❌ 不好：用 * 授予所有 DynamoDB 資源的所有操作
Resource = ["*"]

# ✅ 好：精確鎖定這個 table，只給需要的操作
Resource = [aws_dynamodb_table.items.arn]
Action   = ["dynamodb:GetItem", "dynamodb:PutItem", ...]
```

生產環境的 IAM Policy 應遵循最小權限原則（Least Privilege）。

## 關鍵學習：path parameter

```
route_key = "GET /items/{item_id}"
```

API Gateway 會把 `{item_id}` 解析後放進：
```python
event["pathParameters"]["item_id"]
```

如果 route 設的是 `GET /items/{id}` 但 Lambda 讀 `path_params["item_id"]`，會拿到 None。
**route_key 的 `{}` 名稱和 Python 裡讀的 key 必須一致。**

## 卡關提示

| 症狀 | 原因 |
|------|------|
| POST 回傳 500 | Lambda 沒有 DynamoDB PutItem 權限，確認 TODO 1 |
| GET /items/{id} 回傳 404 | route_key 的 path parameter 名稱和程式碼不一致 |
| `TABLE_NAME` KeyError | Lambda 環境變數 TABLE_NAME 沒設，確認 TODO 2 |
| 4 個 route 都回同樣結果 | Integration 設好了但 Lambda 邏輯要靠 method + path 來分流 |
