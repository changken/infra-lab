# Lab 33 設計文件：Secrets Manager + Lambda 自動輪換 + KMS 加密

**日期**: 2026-05-26
**狀態**: 已確認，準備實作

---

## 範圍

建立 `terraform/labs/33-secrets-manager/`，涵蓋：
- KMS CMK 加密 Secrets Manager Secret
- 模擬資料庫憑證（username/password JSON）
- Lambda 自動輪換（4 步驟生命週期）

---

## 架構

```
Secrets Manager Secret
  {username: "admin", password: "..."}
            │ 加密
            ▼
      KMS CMK Key
            │
            │ 輪換觸發（排程每 1 天 / 手動觸發）
            ▼
  Lambda Rotation Function（4 步驟）
    ├── createSecret  → 產生新密碼，寫入 AWSPENDING 版本
    ├── setSecret     → no-op（lab 無真實 DB）
    ├── testSecret    → 確認 AWSPENDING 版本存在
    └── finishSecret  → AWSPENDING → AWSCURRENT，舊版本 → AWSPREVIOUS
```

---

## TODO 結構

| TODO | Terraform 資源 | 關鍵設定 |
|------|---------------|---------|
| 1 | `aws_kms_key` + `aws_kms_alias` | `enable_key_rotation = true`、key policy |
| 2 | `aws_iam_role` + inline policy | SecretsManager 讀寫 + KMS Decrypt/Encrypt + CloudWatch Logs |
| 3 | `aws_lambda_function` | `filename`、`source_code_hash`、`environment.variables.SECRET_ARN` |
| 4 | `aws_lambda_permission` | `principal = "secretsmanager.amazonaws.com"` |
| 5 | `aws_secretsmanager_secret` + `aws_secretsmanager_secret_version` | `kms_key_id`、`secret_string = jsonencode({...})` |
| 6 | `aws_secretsmanager_secret_rotation` | `rotation_lambda_arn`、`rotation_rules { automatically_after_days = 1 }` |

---

## 檔案清單

```
33-secrets-manager/
├── terraform.tf
├── variables.tf
├── locals.tf
├── main.tf              ← 6 個 TODO
├── outputs.tf
├── terraform.tfvars.example
├── .gitignore
└── README.md
src/
└── rotation_handler.py  ← 4 步驟 rotation Lambda
```

---

## 費用估算

| 資源 | 費用 |
|------|------|
| KMS CMK | $1/月（2 小時 ≈ $0.003）|
| Secrets Manager | $0.40/月/secret（2 小時 ≈ $0.001）|
| Lambda（輪換呼叫）| $0 |
| **合計** | **< $0.10**（🟢 安全）|

---

## 決策記錄

- **KMS CMK 而非 AWS 受管金鑰**：CMK 可自訂 key policy、可稽核、可停用，面試考點
- **輪換週期設為 1 天**：方便 lab 當天手動測試，實際生產建議 30 天
- **不接真實 RDS**：setSecret 步驟設計為 no-op，降低費用與複雜度，同時說明真實場景的差異
