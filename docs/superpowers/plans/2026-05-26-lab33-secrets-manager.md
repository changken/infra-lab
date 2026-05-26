# Lab 33: Secrets Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `terraform/labs/33-secrets-manager/` — 一個填空式 lab，讓使用者學習 KMS CMK + Secrets Manager + Lambda 自動輪換。

**Architecture:** 使用 KMS CMK 加密 Secrets Manager 中的資料庫憑證 JSON，並設定 Lambda rotation function 實作 AWS 4 步驟輪換生命週期（createSecret → setSecret → testSecret → finishSecret）。Rotation Lambda 不接真實 RDS，setSecret 為 no-op，降低費用與複雜度。

**Tech Stack:** Terraform >= 1.0, AWS Provider ~> 5.0, Archive Provider ~> 2.0, Python 3.12（Lambda runtime）

---

## File Map

```
terraform/labs/33-secrets-manager/
├── terraform.tf              # Provider 版本鎖定
├── variables.tf              # region, project, environment
├── locals.tf                 # common_tags
├── main.tf                   # 6 個 TODO（核心學習內容）
├── outputs.tf                # secret_arn, kms_key_id, lambda_name, console_url
├── terraform.tfvars.example  # 範例變數值
├── .gitignore                # *.tfvars, *.tfstate, src/*.zip
└── README.md                 # 學習目標、架構、驗證腳本
src/
└── rotation_handler.py       # 完整 4 步驟 rotation（不是 TODO，降低 Python 干擾）
```

---

## Task 1: 建立目錄與 boilerplate 檔案

**Files:**
- Create: `terraform/labs/33-secrets-manager/terraform.tf`
- Create: `terraform/labs/33-secrets-manager/variables.tf`
- Create: `terraform/labs/33-secrets-manager/locals.tf`
- Create: `terraform/labs/33-secrets-manager/terraform.tfvars.example`
- Create: `terraform/labs/33-secrets-manager/.gitignore`

- [ ] **Step 1: 建立目錄**

```bash
mkdir -p terraform/labs/33-secrets-manager/src
```

- [ ] **Step 2: 建立 terraform.tf**

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}
```

- [ ] **Step 3: 建立 variables.tf**

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "secrets-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
```

- [ ] **Step 4: 建立 locals.tf**

```hcl
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Lab         = "33-secrets-manager"
    ManagedBy   = "terraform"
  }
}
```

- [ ] **Step 5: 建立 terraform.tfvars.example**

```hcl
region      = "us-east-1"
project     = "secrets-lab"
environment = "dev"
```

- [ ] **Step 6: 建立 .gitignore**

```gitignore
*.tfvars
*.tfstate
*.tfstate.backup
.terraform/
src/*.zip
```

- [ ] **Step 7: Commit boilerplate**

```bash
git add terraform/labs/33-secrets-manager/
git commit -m "chore(labs): add lab 33 boilerplate files"
```

---

## Task 2: 建立 Rotation Lambda 原始碼

**Files:**
- Create: `terraform/labs/33-secrets-manager/src/rotation_handler.py`

此檔案提供完整實作（非 TODO）。原因：rotation 契約邏輯是 AWS 固定格式，讓使用者在 Terraform 端學習資源設定才是本 lab 重點。

- [ ] **Step 1: 建立 rotation_handler.py**

```python
import boto3
import json
import os
import secrets
import string


def handler(event, context):
    secret_id = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    client = boto3.client("secretsmanager")

    if step == "createSecret":
        _create_secret(client, secret_id, token)
    elif step == "setSecret":
        _set_secret(client, secret_id, token)
    elif step == "testSecret":
        _test_secret(client, secret_id, token)
    elif step == "finishSecret":
        _finish_secret(client, secret_id, token)
    else:
        raise ValueError(f"Unknown rotation step: {step}")


def _create_secret(client, secret_id, token):
    # Idempotency check: AWSPENDING might already exist from a previous retry
    try:
        client.get_secret_value(
            SecretId=secret_id,
            VersionStage="AWSPENDING",
            VersionId=token,
        )
        return
    except client.exceptions.ResourceNotFoundException:
        pass

    # Preserve username from current secret
    current_str = client.get_secret_value(
        SecretId=secret_id,
        VersionStage="AWSCURRENT",
    )["SecretString"]
    current = json.loads(current_str)

    # Generate cryptographically random 32-char password
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    new_password = "".join(secrets.choice(alphabet) for _ in range(32))

    client.put_secret_value(
        SecretId=secret_id,
        ClientRequestToken=token,
        SecretString=json.dumps({
            "username": current["username"],
            "password": new_password,
        }),
        VersionStages=["AWSPENDING"],
    )


def _set_secret(client, secret_id, token):
    # no-op: this lab has no real DB to update.
    # In production: connect to DB and ALTER USER with the AWSPENDING password.
    pass


def _test_secret(client, secret_id, token):
    # Verify AWSPENDING secret has expected shape
    secret_str = client.get_secret_value(
        SecretId=secret_id,
        VersionStage="AWSPENDING",
        VersionId=token,
    )["SecretString"]
    secret = json.loads(secret_str)

    if "username" not in secret:
        raise ValueError("AWSPENDING secret missing 'username' field")
    if "password" not in secret:
        raise ValueError("AWSPENDING secret missing 'password' field")
    if len(secret["password"]) < 32:
        raise ValueError("AWSPENDING password is too short")


def _finish_secret(client, secret_id, token):
    # Find the current AWSCURRENT version ID
    metadata = client.describe_secret(SecretId=secret_id)
    current_version = None
    for version_id, stages in metadata.get("VersionIdsToStages", {}).items():
        if "AWSCURRENT" in stages:
            if version_id == token:
                return  # Already promoted — idempotent
            current_version = version_id
            break

    # Promote AWSPENDING → AWSCURRENT (old AWSCURRENT → AWSPREVIOUS automatically)
    client.update_secret_version_stage(
        SecretId=secret_id,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
```

- [ ] **Step 2: Commit rotation handler**

```bash
git add terraform/labs/33-secrets-manager/src/rotation_handler.py
git commit -m "feat(labs): add lab 33 rotation lambda source"
```

---

## Task 3: 建立 main.tf（6 個 TODO 填空骨架）

**Files:**
- Create: `terraform/labs/33-secrets-manager/main.tf`

- [ ] **Step 1: 建立 main.tf**

```hcl
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
}

resource "aws_kms_alias" "main" {
  # TODO
}


#--------------------------------------------------------------
# TODO 2: Lambda IAM Role（含 SecretsManager + KMS 權限）
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
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
}

resource "aws_iam_role_policy_attachment" "rotation_basic" {
  # TODO
}

resource "aws_iam_role_policy" "rotation" {
  # TODO
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
}

resource "aws_secretsmanager_secret_version" "initial" {
  # TODO
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
# ⚠️ 注意：設定 rotation 後，AWS 會立刻觸發一次輪換（Immediate Rotation）
#          apply 後約 10-30 秒可以看到密碼已經改變

resource "aws_secretsmanager_secret_rotation" "db" {
  # TODO
}
```

- [ ] **Step 2: Commit main.tf scaffold**

```bash
git add terraform/labs/33-secrets-manager/main.tf
git commit -m "feat(labs): add lab 33 main.tf with TODO scaffolding"
```

---

## Task 4: 建立 outputs.tf

**Files:**
- Create: `terraform/labs/33-secrets-manager/outputs.tf`

- [ ] **Step 1: 建立 outputs.tf**

```hcl
output "secret_arn" {
  description = "Secrets Manager Secret ARN"
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Secrets Manager Secret 名稱"
  value       = aws_secretsmanager_secret.db.name
}

output "kms_key_id" {
  description = "KMS Key ID"
  value       = aws_kms_key.main.key_id
}

output "kms_key_arn" {
  description = "KMS Key ARN"
  value       = aws_kms_key.main.arn
}

output "rotation_lambda_name" {
  description = "Rotation Lambda 函數名稱"
  value       = aws_lambda_function.rotation.function_name
}

output "secrets_console_url" {
  description = "Secrets Manager Console 連結"
  value       = "https://${var.region}.console.aws.amazon.com/secretsmanager/listsecrets"
}
```

- [ ] **Step 2: Commit outputs.tf**

```bash
git add terraform/labs/33-secrets-manager/outputs.tf
git commit -m "feat(labs): add lab 33 outputs.tf"
```

---

## Task 5: 建立 README.md

**Files:**
- Create: `terraform/labs/33-secrets-manager/README.md`

- [ ] **Step 1: 建立 README.md**

````markdown
# Lab 33: Secrets Manager + Lambda 自動輪換 + KMS 加密

> 使用 KMS CMK 加密 Secrets Manager 中的資料庫憑證，並設定 Lambda Rotation Function 實作 4 步驟自動輪換生命週期。

**費用等級**：🟢 安全（< $0.10，KMS $1/月但僅跑 2 小時 ≈ $0.003）

---

## 學習目標

- 理解 Secrets Manager **版本標籤**：`AWSCURRENT` / `AWSPENDING` / `AWSPREVIOUS`
- 理解 Lambda Rotation 的 **4 步驟生命週期**：createSecret → setSecret → testSecret → finishSecret
- 使用 KMS **CMK**（Customer Managed Key）加密 secret，並與 AWS 受管金鑰比較差異
- 理解 `recovery_window_in_days = 0` 的必要性（避免 destroy 後重建衝突）
- 用 AWS CLI 讀取密碼、手動觸發輪換、查看版本歷史

---

## 架構

```
╔═══════════════════════════════════════════════╗
║            Secrets Manager Secret              ║
║   name: secrets-lab-db-credentials            ║
║   {username: "admin", password: "..."}        ║
║                    │ 加密                      ║
║                    ▼                           ║
║             KMS CMK Key                        ║
║   alias: alias/secrets-lab-key                ║
╚═══════════════════════════════════════════════╝
                     │ 輪換觸發
                     ▼
╔═══════════════════════════════════════════════╗
║         Lambda Rotation Function               ║
║   secrets-lab-rotation                        ║
║                                               ║
║   Step 1: createSecret                        ║
║     → 產生 32 位元隨機密碼                     ║
║     → PUT to AWSPENDING version               ║
║                                               ║
║   Step 2: setSecret (no-op in lab)            ║
║     → 生產環境：在 DB 執行 ALTER USER          ║
║                                               ║
║   Step 3: testSecret                          ║
║     → 讀取 AWSPENDING，驗證欄位存在           ║
║                                               ║
║   Step 4: finishSecret                        ║
║     → AWSPENDING → AWSCURRENT                 ║
║     → AWSCURRENT → AWSPREVIOUS               ║
╚═══════════════════════════════════════════════╝
```

---

## 你要做的事

| TODO | 資源 | 關鍵設定 |
|------|------|---------|
| 1 | `aws_kms_key` + `aws_kms_alias` | `enable_key_rotation = true`、`deletion_window_in_days = 7` |
| 2 | `aws_iam_role` + policy attachment + inline policy | SecretsManager 4 個 Action + KMS Decrypt/GenerateDataKey |
| 3 | `aws_lambda_function` | `handler = "rotation_handler.handler"`、`environment.variables` |
| 4 | `aws_lambda_permission` | `principal = "secretsmanager.amazonaws.com"` |
| 5 | `aws_secretsmanager_secret` + `aws_secretsmanager_secret_version` | `kms_key_id`、`recovery_window_in_days = 0` |
| 6 | `aws_secretsmanager_secret_rotation` | `automatically_after_days = 1` |

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

---

## 驗證

### 1. 取得 Secret 名稱

```bash
SECRET_NAME=$(terraform output -raw secret_name)
echo "Secret: $SECRET_NAME"
```

### 2. 讀取目前密碼（AWSCURRENT）

```bash
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --query 'SecretString' \
  --output text | python3 -m json.tool
```

**期望輸出**（apply 剛完成，輪換後密碼已是隨機值）：
```json
{
    "username": "admin",
    "password": "初始或已輪換的密碼..."
}
```

### 3. 查看版本歷史

```bash
aws secretsmanager list-secret-version-ids \
  --secret-id "$SECRET_NAME" \
  --query 'Versions[*].{VersionId:VersionId,Stages:VersionStages}' \
  --output table
```

**期望輸出**：看到 `AWSCURRENT` 和 `AWSPREVIOUS` 兩個版本（apply 後立即輪換一次）。

### 4. 手動觸發輪換

```bash
aws secretsmanager rotate-secret --secret-id "$SECRET_NAME"
echo "等待輪換完成（約 15 秒）..."
sleep 15
```

### 5. 驗證密碼已更換

```bash
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --query 'SecretString' \
  --output text | python3 -m json.tool
```

密碼應與步驟 2 不同。

### 6. 查看輪換 Lambda 的 CloudWatch 日誌

```bash
LAMBDA_NAME=$(terraform output -raw rotation_lambda_name)

# 取得最新 log group
LOG_GROUP="/aws/lambda/$LAMBDA_NAME"

# 列出最近的 log events
aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --order-by LastEventTime \
  --descending \
  --max-items 1 \
  --query 'logStreams[0].logStreamName' \
  --output text | xargs -I {} \
  aws logs get-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name {} \
    --query 'events[*].message' \
    --output text
```

**期望輸出**：看到 4 次 Lambda 呼叫（createSecret、setSecret、testSecret、finishSecret）的日誌。

---

## 結束

```bash
terraform destroy -auto-approve
```

確認輸出包含 `Destroy complete!`。

> **提醒**：KMS CMK 有 `deletion_window_in_days = 7`，destroy 後金鑰進入 7 天待刪除狀態，不會立刻計費。

---

## 成本估算

| 資源 | 費用 |
|------|------|
| KMS CMK（2 小時）| $0.003（$1/月 ÷ 720 小時 × 2）|
| KMS API 呼叫（< 100 次）| $0 |
| Secrets Manager Secret（2 小時）| $0.001（$0.40/月 ÷ 720 × 2）|
| Secrets Manager API 呼叫（< 10 次）| $0 |
| Lambda（輪換呼叫）| $0（免費額度）|
| **合計** | **< $0.01** |

---

## 核心概念釐清

### Secret 版本標籤生命週期

```
apply 後立即輪換（Immediate Rotation）：

  時間軸:
  T+0  [apply]   AWSCURRENT = {password: "InitialPassword123!"}

  T+10s [createSecret] → 建立 AWSPENDING = {password: "xK9#mP2..."}
  T+11s [setSecret]    → no-op
  T+12s [testSecret]   → 驗證 AWSPENDING 有效
  T+13s [finishSecret] → AWSPENDING → AWSCURRENT
                         舊 AWSCURRENT → AWSPREVIOUS

  T+15s [驗證]  AWSCURRENT = {password: "xK9#mP2..."}
                AWSPREVIOUS = {password: "InitialPassword123!"}
```

### KMS CMK vs AWS 受管金鑰

| | AWS 受管金鑰（aws/secretsmanager）| CMK（本 lab）|
|--|-----------------------------------|------------|
| 費用 | 免費 | $1/月 |
| Key Policy 自訂 | 否 | 是 |
| 停用/刪除 | 否 | 可以 |
| 稽核 CloudTrail | 有限 | 完整 |
| 跨帳號共用 | 否 | 可以 |
| **適合場景** | 快速開發 | 生產環境、合規需求 |

### recovery_window_in_days = 0 的必要性

```hcl
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}-db-credentials"
  recovery_window_in_days = 0   # ← 重要！

  # 預設值是 30（天），destroy 後 secret 進入 30 天刪除等待期
  # 若在等待期內重新 apply，會因名稱衝突而失敗：
  # Error: already scheduled for deletion
}
```

---

## 取捨決策（面試常考）

| 情境 | 選擇 | 原因 |
|------|------|------|
| 儲存資料庫密碼 | Secrets Manager | 有自動輪換、版本管理；SSM Parameter Store 無此功能 |
| 儲存非敏感設定 | SSM Parameter Store | 免費，Secrets Manager $0.40/月/secret |
| 需要自動換密碼 | Secrets Manager + Lambda Rotation | 唯一原生支援自動輪換的服務 |
| 需要合規稽核 | Secrets Manager + KMS CMK | 完整 CloudTrail 紀錄，可證明「只有授權者能解密」 |

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `apply` 後密碼沒有變化 | `aws_secretsmanager_secret_rotation` 資源設定有誤，檢查 `rotation_lambda_arn` 是否指向正確 ARN |
| Lambda 輪換失敗（logs 有 AccessDenied）| IAM policy 缺少 `secretsmanager:PutSecretValue` 或 `kms:GenerateDataKey` |
| `destroy` 後重新 `apply` 出現 secret name 衝突 | 缺少 `recovery_window_in_days = 0`，或等 30 秒再 apply |
| `rotation` 一直 PENDING | Lambda permission 缺少（TODO 4），Secrets Manager 無法呼叫 Lambda |
| `kms:Decrypt` AccessDenied | IAM policy Resource 的 ARN 不正確，確認用 `aws_kms_key.main.arn` |
| `terraform validate` 失敗 | 正常：resource body 還是 `# TODO`，填完所有欄位後再執行 |
````

- [ ] **Step 2: Commit README.md**

```bash
git add terraform/labs/33-secrets-manager/README.md
git commit -m "docs(labs): add lab 33 README with verification guide"
```

---

## Task 6: 初始化並鎖定 Provider 版本

**Files:**
- Create: `terraform/labs/33-secrets-manager/.terraform.lock.hcl` (generated)

- [ ] **Step 1: 切換到 lab 目錄並執行 terraform init**

```bash
cd terraform/labs/33-secrets-manager
terraform init
```

Expected output:
```
Terraform has been successfully initialized!
```

- [ ] **Step 2: 確認 lock file 已生成**

```bash
ls .terraform.lock.hcl
```

Expected: 檔案存在，內容包含 `hashicorp/aws` 和 `hashicorp/archive` 的版本雜湊。

- [ ] **Step 3: Commit lock file**

```bash
git add .terraform.lock.hcl
git commit -m "chore(labs): add lab 33 terraform lock file"
```

---

## Task 7: 更新 Roadmap 標記 Lab 33

**Files:**
- Modify: `terraform/docs/roadmap-v2.md`

- [ ] **Step 1: 更新 roadmap-v2.md 的 Phase 1-D 表格**

在 `terraform/docs/roadmap-v2.md` 中，找到這一行：
```
| 33 | `33-secrets-manager` | Secrets Manager + Lambda 自動輪換 + KMS 加密 | < $0.10 | DVA, SOA |
```

改為：
```
| 33 🚧 | `33-secrets-manager` | Secrets Manager + Lambda 自動輪換 + KMS 加密 | < $0.10 | DVA, SOA |
```

- [ ] **Step 2: Commit roadmap update**

```bash
git add terraform/docs/roadmap-v2.md
git commit -m "docs(roadmap): mark lab 33 as scaffolded"
```

---

## Self-Review

**Spec coverage check:**
- ✅ KMS CMK (`aws_kms_key` + `aws_kms_alias`) → Task 3, TODO 1
- ✅ Lambda Rotation 4 步驟 → Task 2 rotation_handler.py
- ✅ `aws_secretsmanager_secret` with `kms_key_id` → Task 3, TODO 5
- ✅ `aws_secretsmanager_secret_rotation` → Task 3, TODO 6
- ✅ IAM role with SecretsManager + KMS permissions → Task 3, TODO 2
- ✅ `aws_lambda_permission` with secretsmanager principal → Task 3, TODO 4
- ✅ 驗證腳本（get-secret-value, rotate-secret, list-secret-version-ids）→ Task 5 README
- ✅ 費用估算 < $0.10 → Task 5 README
- ✅ `recovery_window_in_days = 0` 教學 → TODO 5 comment + README
- ✅ .terraform.lock.hcl → Task 6

**Placeholder scan:** 無 TBD/TODO 殘留於計劃本身（main.tf 的 TODO 是教學用途，屬正常）。

**Type consistency:** rotation_handler.py 的 `handler` function name 與 main.tf TODO 3 的 `handler = "rotation_handler.handler"` 一致。
