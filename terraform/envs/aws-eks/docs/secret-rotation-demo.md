# Secret Rotation Demo — Secrets Manager + Lambda + ESO

## 架構概覽

```
Secrets Manager（每 30 天自動觸發）
   │
   ▼
Lambda: infra-lab-dev-rotate-secret
   │
   ├─ createSecret  → secrets.token_hex(16) → AWSPENDING
   ├─ setSecret     → no-op（自產 key，無外部服務）
   ├─ testSecret    → 驗證 AWSPENDING JSON 格式
   └─ finishSecret  → AWSPENDING 升格為 AWSCURRENT
                           │
                           │（refreshInterval: 1h）
                           ▼
                      ESO ExternalSecret
                           │
                           ▼
                      K8s Secret: custom-app-secrets
                           │
                           ▼
                      Pod 重啟後拿到新 chat-api-key
```

**設計重點**：Rotation 邏輯完全在 AWS 側，不需要改任何 K8s 或 GitOps 設定。ESO 自動把新值同步到 K8s Secret。

---

## 為什麼需要 Rotation？

| 不 rotate | rotate |
|-----------|--------|
| 同一把 key 永遠有效 | 每 30 天換新，即使洩漏也有時間窗口限制 |
| 洩漏後需手動發現 + 撤銷 | 到期自動失效 |
| 需記得手動換 | 全自動，零人工介入 |

---

## Terraform 資源（rotation.tf）

### 資源關係圖

```
archive_file.rotate_secret (zip)
   └── aws_lambda_function.rotate_secret
         ├── aws_iam_role.rotate_secret_lambda
         │     └── aws_iam_role_policy  (logs + secretsmanager 只限 custom-app secret)
         ├── aws_lambda_permission.secrets_manager  (allow Secrets Manager to invoke)
         └── aws_secretsmanager_secret_rotation.custom_app
               └── rotation_rules { automatically_after_days = 30 }
```

### Lambda IAM Policy（最小權限）

```hcl
Action = [
  "secretsmanager:GetSecretValue",
  "secretsmanager:PutSecretValue",
  "secretsmanager:DescribeSecret",
  "secretsmanager:UpdateSecretVersionStage",
]
Resource = aws_secretsmanager_secret.custom_app.arn  # 只允許此 secret
```

---

## Lambda Rotation 邏輯（rotate_secret.py）

### 4-Step Protocol

AWS Secrets Manager rotation 固定呼叫 Lambda 4 次，每次 `event["Step"]` 不同：

| Step | 做什麼 | 本 Lab 實作 |
|------|--------|------------|
| `createSecret` | 產生新值，存成 `AWSPENDING` | `secrets.token_hex(16)` → 32 位 hex |
| `setSecret` | 把新值推送到外部服務 | no-op（self-generated，無外部服務） |
| `testSecret` | 驗證新值可用 | 確認 `AWSPENDING` 有 `chat-api-key` 且非空 |
| `finishSecret` | `AWSPENDING` 升格為 `AWSCURRENT` | `update_secret_version_stage` |

### 冪等設計

`createSecret` 開頭先檢查 `AWSPENDING` 是否已存在，避免重試時重複產生：
```python
try:
    client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
    return  # 已存在，跳過
except client.exceptions.ResourceNotFoundException:
    pass
```

### Secret 格式保留其他 key

```python
# 讀取現有 JSON → 只更新 chat-api-key → 寫回
current = json.loads(client.get_secret_value(...)["SecretString"])
current["chat-api-key"] = secrets.token_hex(16)
client.put_secret_value(SecretString=json.dumps(current), VersionStages=["AWSPENDING"])
```
未來若 secret 裡有其他欄位，rotation 不會把它們清掉。

---

## 驗證結果

### Rotation 狀態
```json
{
  "rotation_enabled": true,
  "rotation_lambda": "arn:aws:lambda:us-east-1:661515655645:function:infra-lab-dev-rotate-secret",
  "rotation_rules": { "AutomaticallyAfterDays": 30 },
  "last_rotated": "2026-06-24T09:10:25+08:00"
}
```

### 手動觸發 rotation
```bash
aws secretsmanager rotate-secret \
  --secret-id infra-lab-dev/custom-app \
  --region us-east-1

# 觸發後確認新值
aws secretsmanager get-secret-value \
  --secret-id infra-lab-dev/custom-app \
  --region us-east-1 \
  --query 'SecretString' --output text
# {"chat-api-key": "c9cca2dfd3cd82c4df0ed59bc0502464"}
```

### ESO 強制立即同步
```bash
# rotation 後 ESO 最慢 1h 同步，若要立即生效：
kubectl annotate externalsecret custom-app-secrets -n custom-app \
  force-sync=$(date +%s) --overwrite

# 確認 K8s Secret 已更新
kubectl get secret custom-app-secrets -n custom-app \
  -o jsonpath='{.data.chat-api-key}' | base64 -d
```

---

## 完整時序

```
t=0        Secrets Manager 觸發 Lambda（排程或手動）
t=1s       Step: createSecret → secrets.token_hex(16) → AWSPENDING
t=2s       Step: setSecret    → no-op
t=3s       Step: testSecret   → 驗證 AWSPENDING OK
t=4s       Step: finishSecret → AWSPENDING 升格 AWSCURRENT
t=5s       rotation 完成，Secrets Manager 記錄 last_rotated

t=0~3600s  ESO refreshInterval 到期
t=?        ESO GetSecretValue → 取得新值 → 更新 K8s Secret

t=next restart  Pod 重啟 → os.Getenv("CHAT_API_KEY") 拿到新 key ✅
```

---

## 注意：Pod 需重啟才能拿到新值

目前 app 在啟動時讀取 env var（`os.Getenv`），Secret rotation 後需要 Pod 重啟才生效。

有幾個方案：

| 方案 | 說明 | 複雜度 |
|------|------|--------|
| **手動重啟** | `kubectl rollout restart deployment/custom-app -n custom-app` | 低 |
| **Stakater Reloader** | Watch Secret 變化 → 自動 rolling restart | 中 |
| **掛載為檔案** | CSI Secret Store Driver，app 讀檔案而非 env var | 高 |

Lab 環境建議手動重啟即可。

---

## 延伸閱讀

- [eso-demo.md](./eso-demo.md) — ESO 安裝與 ExternalSecret 設定（本 Lab 的前置步驟）
- [irsa-demo.md](./irsa-demo.md) — IRSA（Lambda rotation 與 ESO 都用了同樣的身份驗證機制）
- AWS 官方：[Rotation function templates](https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_available-rotation-templates.html)
