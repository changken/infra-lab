# Lab 09: Lambda + S3 Event Trigger

上傳檔案到 S3，自動觸發 Lambda 處理。
**幾乎免費** — S3 儲存 + Lambda 呼叫次數都在 Free Tier 內。

## 學習目標

- S3 Event Notification：S3 怎麼「通知」Lambda 有新檔案
- Lambda Permission 的 `principal`：S3 vs API Gateway 的差異
- `depends_on` 的實際用途：Notification 必須等 Permission 建好
- `filter_prefix` / `filter_suffix`：只處理特定路徑或副檔名的檔案
- CloudWatch Logs：觀察 Lambda 被觸發的 log

## 架構

```
你執行 aws s3 cp → S3 bucket（uploads/ 路徑）
                      ↓ s3:ObjectCreated 事件
                   Lambda（processor.handler）
                      ↓ s3:GetObject
                   讀取檔案內容 → CloudWatch log
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_s3_bucket` | 私有 bucket，不需要任何公開設定 |
| 2 | `aws_iam_role_policy` | S3 GetObject 權限，Resource 要加 `/*` |
| 3 | `aws_lambda_function` | handler = `processor.handler` |
| 4 | `aws_lambda_permission` + `aws_s3_bucket_notification` | S3 principal + 觸發條件 |

再補完 `outputs.tf` 的 1 個 TODO（upload_command）。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：7 to add
terraform apply
```

**預期 plan：7 個 to add**
（random_id + S3 + IAM Role + Basic Policy + S3 Policy +
 Lambda + Permission + Notification = 8，random_id 是 meta resource）

### 驗證

```bash
# 1. 上傳測試檔案
terraform output -raw upload_command | bash
# 或手動：
BUCKET=$(terraform output -raw bucket_name)
echo "hello from terraform lab 09" > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://$BUCKET/uploads/test.txt

# 2. 等幾秒後，查看 Lambda log
aws logs tail /aws/lambda/s3-file-processor --follow
# 應該看到：New file: s3://.../.../test.txt (N bytes)
# 以及：Content preview: hello from terraform lab 09
```

### 結束

```bash
# ⚠️ 先清空 bucket（非空 bucket 無法 destroy）
BUCKET=$(terraform output -raw bucket_name)
aws s3 rm s3://$BUCKET --recursive

terraform destroy -auto-approve
```

## 成本

**< $0.10**。S3 PUT 請求 + Lambda 呼叫次數都極少。

## 關鍵：Permission 的 principal 差異

| 觸發來源 | principal |
|---------|-----------|
| API Gateway | `apigateway.amazonaws.com` |
| S3 | `s3.amazonaws.com` |
| EventBridge | `events.amazonaws.com` |
| SNS | `sns.amazonaws.com` |

每種觸發來源都有不同的 `principal`，且 `source_arn` 的格式也不同。

## 關鍵：為什麼 S3 Notification 需要 depends_on？

```
建立流程（正確）：
  Lambda Permission → S3 Notification
                     （S3 在設定時會驗證能否呼叫 Lambda）

建立流程（錯誤，沒有 depends_on）：
  Lambda Permission ← S3 Notification 同時建立
                     → S3 驗證失敗 → apply 報錯或靜默失敗
```

## 卡關提示

| 症狀 | 原因 |
|------|------|
| 上傳後 Lambda 沒被觸發 | Notification 的 `filter_prefix` 路徑不符，試試不加 filter |
| Lambda log 沒出現 | Permission 的 principal 或 source_arn 錯誤 |
| Lambda 被觸發但讀不到內容 | S3 IAM Policy 的 Resource 少了 `/*` |
| destroy 失敗 | Bucket 非空，先執行 `aws s3 rm s3://$BUCKET --recursive` |
