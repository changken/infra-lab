# Lab 07: Lambda + API Gateway

在 Lambda 前面加一個 HTTP API，讓它能用 URL 呼叫。
**幾乎免費** — API Gateway HTTP API + Lambda 全在 Free Tier 內。

## 學習目標

- API Gateway v2（HTTP API）vs v1（REST API）的差異
- Integration：API Gateway 和 Lambda 之間的橋接
- Route：`GET /hello` 格式的路由設定
- `aws_lambda_permission`：為什麼要明確授權給 API Gateway
- `$default` stage + `auto_deploy`：最簡單的部署設定

## 架構

```
curl / 瀏覽器
  → API Gateway HTTP API（aws_apigatewayv2_api）
      → $default stage（aws_apigatewayv2_stage）
          → GET /hello route（aws_apigatewayv2_route）
              → Integration（aws_apigatewayv2_integration）
                  → Lambda Function（hello.handler）
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_lambda_function` | 跟 Lab 06 一樣（複習） |
| 2 | `aws_apigatewayv2_api` + `stage` | HTTP API + $default stage |
| 3 | `aws_apigatewayv2_integration` + `route` | 接線：API → Lambda |
| 4 | `aws_lambda_permission` | 授權 API Gateway 呼叫 Lambda |

再補完 `outputs.tf` 的 1 個 TODO（curl_command）。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：6 to add
terraform apply
```

**預期 plan：6 個 to add**
（IAM Role + Policy Attachment + Lambda + API + Stage + Integration + Route + Permission = 8，
 IAM 已預填 = 6 個 TODO）

### 驗證（apply 完後）

```bash
# 用 output 的指令
terraform output -raw curl_command

# 或直接：
curl "$(terraform output -raw hello_url)?name=Terraform"
```

應該回傳：
```json
{"message": "Hello, Terraform!", "method": "GET", "path": "/hello", "environment": "dev"}
```

### 結束

```bash
terraform destroy -auto-approve
```

## 成本

**$0**。API Gateway HTTP API：前 100 萬次 / 月免費。Lambda：前 100 萬次免費。

## 為什麼需要 Lambda Permission？

Lambda 預設**拒絕所有外部呼叫**，就算 API Gateway 設定好了，沒有明確授權還是會報 403：

```
{"message":"Internal Server Error"}
# CloudWatch log 裡才看得到真正的錯誤：
# User: arn:aws:iam:... is not authorized to perform: lambda:InvokeFunction
```

`source_arn` 裡的兩個 `*`：
```
${execution_arn}/*/*
                 ↑ ↑
                 │ └── HTTP method（GET/POST/...）
                 └──── stage name（$default/prod/...）
```
用 `*` 允許所有 stage 和 method，避免日後換 stage 又要改 permission。

## API Gateway v2 vs v1

| | HTTP API（v2）| REST API（v1）|
|--|--------------|--------------|
| 費用 | 更便宜 | 較貴 |
| 設定 | 簡單 | 複雜 |
| 功能 | 基本夠用 | 功能更多（throttling, WAF...）|
| 適合 | 練習 / 一般 API | 企業級 / 複雜需求 |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `curl` 回傳 `{"message":"Internal Server Error"}` | Lambda Permission 沒設，看 CloudWatch log 確認 |
| `curl` 回傳 404 | Route 的 `route_key` 格式錯，確認是 `"GET /hello"` 不是 `"/hello"` |
| `target` 格式報錯 | 要用 `"integrations/${aws_apigatewayv2_integration.lambda.id}"` 加前綴 |
| plan 顯示 8 to add（不是 6）| 正常，IAM Role 和 Policy Attachment 也是你寫的（已預填） |
