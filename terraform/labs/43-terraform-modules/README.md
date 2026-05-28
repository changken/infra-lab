# Lab 43：Terraform 模組化重構

> **場景**：把 Labs 21-42 中反覆出現的模式（VPC、Lambda+API GW、CloudWatch Alarms）抽成可重用 modules，並用 S3 Remote State + DynamoDB Lock 模擬團隊協作環境。  
> **費用等級**：🟢 安全（< $0.10，主要是 Lambda + API GW，幾乎免費）

---

## 學習目標

完成本 lab 後，你能夠：

- 寫一個標準 Terraform Module（`variables.tf` / `main.tf` / `outputs.tf` 三件組）
- 理解 **Module 邊界**：模組內不能直接引用其他模組的資源，只能透過 `output → variable` 傳遞
- 設定 **S3 Remote Backend + DynamoDB State Lock**，模擬多人協作時的狀態管理
- 執行 `terraform init -migrate-state` 把本地 state 遷移到 S3
- 理解 **Bootstrap 問題**（雞與蛋）：遠端 state 的基礎設施本身也需要 Terraform 管理，但不能用自己的遠端 state 存放

---

## 目錄結構

```
43-terraform-modules/
├── bootstrap/              ← 步驟一：建立 Remote State 基礎設施
│   └── main.tf             ← S3 Bucket + DynamoDB Table（使用 local backend）
│
├── modules/                ← 可重用模組定義
│   ├── networking/         ← TODO 1: VPC + Subnets + IGW + Route Table
│   │   ├── variables.tf    ← 已提供（模組輸入定義）
│   │   ├── main.tf         ← 填空
│   │   └── outputs.tf      ← 已提供（模組輸出定義）
│   │
│   ├── serverless-api/     ← TODO 2: Lambda + API Gateway HTTP API
│   │   ├── variables.tf    ← 已提供
│   │   ├── main.tf         ← 填空
│   │   └── outputs.tf      ← 已提供
│   │
│   └── observability/      ← TODO 3: SNS + CloudWatch Alarms
│       ├── variables.tf    ← 已提供
│       ├── main.tf         ← 填空
│       └── outputs.tf      ← 已提供
│
├── src/
│   └── hello.py            ← 已提供（Lambda function）
│
├── terraform.tf            ← TODO 5: S3 backend 設定（bootstrap 後填入）
├── variables.tf
├── locals.tf
├── main.tf                 ← TODO 4: 呼叫三個 modules
└── outputs.tf              ← TODO 6: 聚合 module 輸出
```

---

## 模組設計

```
Root Configuration
      │
      ├── module "network" (./modules/networking)
      │     輸入: project, environment, tags
      │     輸出: vpc_id, public_subnet_ids ──────────┐
      │                                               │（這個 lab 暫不使用，
      │                                               │  展示 module 獨立性）
      ├── module "api" (./modules/serverless-api)
      │     輸入: project, environment,
      │           source_zip_path, source_code_hash
      │     輸出: api_endpoint, function_name ────────┐
      │                                               │ 跨模組傳遞
      └── module "monitoring" (./modules/observability)
            輸入: project, environment,
                  lambda_function_name ←──────────────┘
            輸出: sns_topic_arn
```

---

## 你要做的事

| TODO | 位置 | 說明 |
|------|------|------|
| 1 | `modules/networking/main.tf` | VPC + IGW + Subnets（count）+ Route Table |
| 2 | `modules/serverless-api/main.tf` | Lambda + IAM + API GW HTTP API |
| 3 | `modules/observability/main.tf` | SNS + Email 訂閱 + CloudWatch Alarms |
| 4 | `main.tf`（根）| 呼叫三個 modules，跨 module 傳遞 function_name |
| 5 | `terraform.tf`（根）| Bootstrap 後填入 S3 backend 設定，執行 migrate-state |
| 6 | `outputs.tf`（根）| 用 `module.<name>.<output>` 聚合輸出 |

---

## 指令流程

### 階段一：Bootstrap Remote State

```bash
# 進入 bootstrap 目錄（它有自己獨立的 Terraform config）
cd bootstrap
terraform init
terraform apply -auto-approve

# 查看 backend 設定（複製這段內容）
terraform output -raw backend_config
```

輸出範例：
```hcl
backend "s3" {
  bucket         = "tf-lab-state-a1b2c3d4"
  key            = "43-terraform-modules/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "tf-lab-state-lock"
  encrypt        = true
}
```

回到上層目錄並填入 `terraform.tf`：
```bash
cd ..
# 編輯 terraform.tf，取消 backend "s3" 的註解並填入上述值
```

### 階段二：實作三個 Modules（TODO 1-3）

完成各模組的 `main.tf` 後，驗證語法：
```bash
cd modules/networking && terraform fmt && cd ../..
cd modules/serverless-api && terraform fmt && cd ../..
cd modules/observability && terraform fmt && cd ../..
```

### 階段三：完成 Root Config（TODO 4-6）

```bash
# 複製 tfvars
cp terraform.tfvars.example terraform.tfvars

# 初始化（若已設定 S3 backend，加上 -migrate-state）
terraform init                      # 第一次（local backend）
# 或
terraform init -migrate-state       # 設定 S3 backend 後

# 格式化 + 驗證
terraform fmt -recursive            # 格式化所有子目錄（含 modules）
terraform validate

# 預覽（確認三個 module 各自的資源）
terraform plan

# 部署
terraform apply -auto-approve
```

---

## 驗證方式

### 步驟 1：確認模組資源已建立

```bash
# 查看所有建立的資源（按 module 分組）
terraform state list

# 預期輸出（資源名稱含 module prefix）：
# module.network.aws_vpc.main
# module.network.aws_subnet.public[0]
# module.network.aws_subnet.public[1]
# module.api.aws_lambda_function.this
# module.api.aws_apigatewayv2_api.this
# module.monitoring.aws_sns_topic.alarms
# module.monitoring.aws_cloudwatch_metric_alarm.lambda_errors
```

### 步驟 2：測試 API

```bash
API=$(terraform output -raw api_endpoint)
curl -s $API/ | jq .

# 預期輸出：
# {"message": "Hello from modularized Terraform!", "lab": "43-terraform-modules", "path": "/"}
```

### 步驟 3：確認 Remote State（S3 Backend）

```bash
# 查看 state 是否已存到 S3
STATE_BUCKET=$(cd bootstrap && terraform output -raw state_bucket_name)
aws s3 ls s3://$STATE_BUCKET/43-terraform-modules/

# 預期看到 terraform.tfstate 檔案
```

### 步驟 4：模擬狀態鎖定（DynamoDB Lock）

```bash
# 在終端機 1 執行 plan（需要幾秒）
terraform plan

# 在終端機 2（同時）嘗試 apply
terraform apply
# 預期輸出：Error acquiring the state lock: ConditionalCheckFailedException
```

### 步驟 5：查看 Terraform State 結構

```bash
# 查看特定 module 的 resource 詳細資訊
terraform state show module.api.aws_lambda_function.this

# 查看 module output
terraform output -json
```

---

## 結束

```bash
# 銷毀根配置資源
terraform destroy -auto-approve

# 銷毀 Bootstrap 資源（S3 bucket + DynamoDB）
# 注意：S3 state bucket 的 force_destroy = true，直接 destroy 即可
cd bootstrap
terraform destroy -auto-approve
```

> **順序很重要**：先 destroy 根配置（state 存在 S3），再 destroy bootstrap（不能在 state 存的 bucket 被刪除後才 destroy）

---

## 成本估算

| 資源 | 計費模式 | 費用 |
|------|---------|------|
| Lambda | 前 1M 次免費 | $0.00 |
| API GW HTTP API | 前 1M 次/月免費 | $0.00 |
| S3 State Bucket | 幾 KB，< $0.001 | $0.00 |
| DynamoDB Lock Table | PAY_PER_REQUEST，< 100 ops | $0.00 |
| CloudWatch Alarms × 2 | $0.10/alarm/月 | $0.00 |
| **合計** | | **< $0.01** |

---

## 架構決策紀錄（ADR）

### ADR-1：為什麼要 Remote State？Local State 不夠嗎？

**決策**：用 S3 + DynamoDB 作為 Terraform State Backend，而非預設的本地 `.tfstate` 檔案。

**理由**：

| | Local State | S3 Remote State |
|-|------------|----------------|
| 多人協作 | 不行（每人 state 不同步）| ✅ 所有人共用同一份 state |
| 狀態鎖定 | 無（可能 race condition）| ✅ DynamoDB 防止並行 apply |
| 狀態備份 | 手動（丟了就完了）| ✅ S3 版本控制自動備份 |
| CI/CD | 困難（state 存哪？）| ✅ Pipeline 存取 S3 |

**Bootstrap 問題**：建立 S3 bucket 本身需要 Terraform，但這段 Terraform 的 state 不能存在尚未建立的 bucket 裡。解法是 bootstrap 目錄用 local backend，bootstrap 完成後再遷移主配置到 remote。

**結論**：任何有多人協作或 CI/CD 的專案，都必須用 remote state。

---

### ADR-2：為什麼三個 module 而不是一個大的 module 或多個小 modules？

**決策**：按「關注點分離」原則，分為 `networking`、`serverless-api`、`observability` 三個模組。

**理由**：
- **可重用邊界**：`serverless-api` 可以在沒有 VPC 的情況下使用（Lambda 不需要 VPC）。`observability` 可以監控任何 Lambda，不限於本 lab 的。分開才能分別重用。
- **變更隔離**：修改 `networking` 不影響 `serverless-api`。單一巨大模組的任何改動都需要重新規劃所有資源。
- **測試單元**：可以分別對每個模組寫 Terratest 測試。

**模組太小的反例**：把每個 `aws_iam_role` 包成一個模組 — 過度抽象，引入比直接寫更多複雜度。

**結論**：模組的粒度以「可以獨立重用的最小功能單元」為標準。

---

### ADR-3：為什麼 `modules/observability` 接受 `lambda_function_name` 字串而不是 Lambda 資源引用？

**決策**：`observability` module 的 variable 設計為 `lambda_function_name = string`，而不是傳入 Lambda 資源 object。

**理由**：
- **模組邊界（Module Boundary）**：Terraform module 不允許跨模組引用資源（`module.api.aws_lambda_function.this` 不是合法的跨模組引用）。模組只能透過 `output` 暴露值，外部透過 `variable` 接收。這是 Terraform 的核心設計原則。
- **最小接口原則**：`observability` 模組只需要 Lambda 的名稱就能設定 CloudWatch Alarm Dimension，不需要整個 Lambda 資源的所有屬性。傳入字串比傳入物件更簡單、更低耦合。
- **可替換性**：這樣設計後，即使 Lambda 由其他方式建立（不是 `serverless-api` 模組），`observability` 模組也能使用。

**結論**：模組 interface 設計原則：傳遞最小必要信息（通常是 ID/ARN/名稱），而非整個資源物件。

---

## 常見問題

| 症狀 | 原因 | 解法 |
|------|------|------|
| `terraform init` 報 backend 設定錯誤 | S3 bucket 或 DynamoDB table 不存在 | 先執行 `cd bootstrap && terraform apply` |
| `Error acquiring the state lock` | 另一個 apply 正在進行，或上次 apply 異常終止殘留 lock | `terraform force-unlock <lock-id>` |
| Module 資源名稱衝突 | 同一 module 被呼叫兩次但未傳入不同 project/environment | 確認每次 module 呼叫傳入不同的 `project` 或 `environment` |
| `terraform init` 後 module 找不到 | source 路徑錯誤 | 確認 `source = "./modules/networking"` 有 `./` 前綴（相對路徑） |
| `source_zip_path` 傳入 module 後 Lambda 更新不觸發 | `source_code_hash` 未傳入或傳入錯誤 | 確認 `source_code_hash = data.archive_file.hello.output_base64sha256` |
| `terraform fmt -recursive` 報錯 | modules 子目錄的 .tf 語法錯誤 | 先個別進各模組目錄 validate |
| destroy 順序錯誤導致 state 遺失 | 先 destroy bootstrap 再 destroy 根配置 | 務必先 `terraform destroy`（根），再 `cd bootstrap && terraform destroy` |

---

## 延伸練習

完成基本 6 個 TODO 後，可嘗試：

1. **多環境**：在 `main.tf` 中用不同 `environment` 值呼叫 `module "api"` 兩次（模擬 dev + staging 共存）
2. **Module 版本鎖定**：把 modules 推到 GitHub，改用 `source = "github.com/user/repo//modules/networking?ref=v1.0.0"`
3. **Terratest**：在 `modules/serverless-api` 加 Go 測試，呼叫 API 端點驗證回傳

---

## 面試故事

> 「我在 Lab 43 做了 Terraform 模組化重構。把 Labs 21-42 中重複出現的三個模式——VPC 網路、Lambda+API GW、CloudWatch 告警——各自抽成獨立模組，每個模組有自己的 `variables.tf` 和 `outputs.tf`，對外只暴露最小必要接口。
>
> 模組間的資料傳遞是關鍵設計：`observability` 模組監控 `serverless-api` 模組建立的 Lambda，但它接受的是 `lambda_function_name` 字串變數，而不是資源引用。這是 Terraform 模組邊界的核心原則——模組只能透過 output-variable 對話，不能跨邊界直接引用。
>
> 另一個重點是 Remote State Bootstrap 問題：S3 bucket 本身要用 Terraform 建立，但這段 Terraform 的 state 不能放進尚未存在的 bucket。解法是 bootstrap 目錄用 local backend，建完後用 `terraform init -migrate-state` 遷移。面試官很喜歡這個問題，因為它展示了你真正理解 Terraform state 的運作原理。」

---

*建立於 2026-05-28*
