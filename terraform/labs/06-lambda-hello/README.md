# Lab 06: Lambda Hello World

建立第一個 Lambda Function，理解 Serverless 的基本運作方式。
**完全免費** — Lambda 每月 100 萬次呼叫都在 Free Tier 內。

## 學習目標

- Lambda 需要 IAM Role 才能執行（最常見的初學者卡關點）
- `assume_role_policy`：讓 AWS 服務「扮演」這個 Role 的機制
- `archive_file` data source：把 Python 打包成 zip
- `handler`：`檔名.函式名` 的格式
- `source_code_hash`：程式碼沒變就不重新上傳

## 架構

```
你的電腦
└── src/hello.py
    → archive_file（打包成 zip）
        → aws_lambda_function（上傳到 AWS）
            ← aws_iam_role（執行身份）
                ← AWSLambdaBasicExecutionRole（寫 CloudWatch log 的權限）
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_iam_role` | `assume_role_policy`：允許 lambda.amazonaws.com 使用這個 Role |
| 2 | `aws_iam_role_policy_attachment` | 掛上內建 Policy，讓 Lambda 能寫 log |
| 3 | `aws_lambda_function` | 主體：runtime/handler/role/程式碼 |

再補完 `outputs.tf` 的 1 個 TODO（invoke_command）。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：3 to add
terraform apply
```

**預期 plan：3 個 to add**（IAM Role + Policy Attachment + Lambda）

### 驗證（apply 完後）

```bash
terraform output invoke_command
# 複製輸出的指令執行，應該看到回傳：
# {"statusCode": 200, "body": "{\"message\": \"Hello, Terraform!\", ...}"}
```

或直接用 AWS CLI：

```bash
aws lambda invoke \
  --function-name hello-world \
  --payload '{"name": "Terraform"}' \
  /tmp/response.json && cat /tmp/response.json
```

```powershell
[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"name":"Terraform"}'))

'{"name":"Terraform"}' | ConvertTo-Json | ForEach-Object { [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($_)) }

function ConvertTo-Base64 {
    param([string]$Text)
    [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text))
}

# 使用
ConvertTo-Base64 '{"name":"Terraform"}'

$json = '{"name":"Terraform"}'
$base64 = ConvertTo-Base64 $json
aws lambda invoke --function-name hello-world --payload $base64 /tmp/response.json
```

### 結束

```bash
terraform destroy -auto-approve
```

## 成本

**$0**。Lambda Free Tier：100 萬次呼叫 + 400,000 GB-秒 / 月，永久免費。

## Lambda 核心概念

### IAM Role 為什麼必要？

Lambda 本身沒有「身份」，它需要一個 IAM Role 告訴 AWS：
- 「我是誰」（Role）
- 「我能做什麼」（Policy）

沒有 Role → Lambda 連寫 CloudWatch log 都不行。

### handler 格式

```
hello.handler
│     └── 函式名（Python 裡的 def handler）
└── 檔名（hello.py，不含副檔名）
```

### source_code_hash 的用途

```hcl
source_code_hash = data.archive_file.lambda_zip.output_base64sha256
```

Terraform 用這個 hash 判斷「程式碼有沒有改過」：
- 沒改 → 不重新上傳（節省時間）
- 改了 → 自動重新上傳並更新 Lambda

等同於 S3 lab 裡的 `etag = filemd5()`，原理相同。

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `assume_role_policy` JSON 格式報錯 | 用 `jsonencode()` 而非手寫 JSON string |
| `handler` 找不到 | 格式是 `檔名.函式名`，確認 `hello.py` 在 `src/` 裡 |
| `The role defined for the function cannot be assumed by Lambda` | `assume_role_policy` 的 Principal 沒設對，要是 `lambda.amazonaws.com` |
| `apply` 後 invoke 沒有 log | Policy Attachment 沒掛上，Lambda 無法寫 CloudWatch |

## 進階挑戰（選做）

- 加一個 `timeout = 10`（秒），觀察 plan 變化
- 改 `hello.py` 的回應內容，`apply` 後觀察 Terraform 怎麼描述程式碼更新
- 在 AWS Console 的 Lambda 頁面找到你的函式，用 Test 功能直接觸發
