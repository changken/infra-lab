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
