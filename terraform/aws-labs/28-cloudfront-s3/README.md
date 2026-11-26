# Lab 28: CloudFront + S3（OAC 零公開存取靜態網站）

> 用 Origin Access Control 讓 CloudFront CDN 服務私有 S3 Bucket 的靜態網站，S3 完全不開 Public Access。

**費用等級**：🟢 安全（CloudFront 免費方案 1TB 流量/月，S3 < $0.01）

---

## 學習目標

- 理解 OAC（Origin Access Control）和舊版 OAI 的差異
- 掌握 `bucket_regional_domain_name` vs `bucket_domain_name` 的區別
- 設計 Bucket Policy 鎖定到特定 CloudFront Distribution ARN
- 理解為何 OAC 下 S3 對不存在的檔案回傳 403（需要 `custom_error_response`）
- 學會 CloudFront Invalidation（更新內容後清除快取）

---

## 架構

```
使用者瀏覽器
    │
    │ HTTPS（CloudFront 預設憑證）
    ▼
CloudFront Edge（全球 450+ 節點）
    │
    │ SigV4 簽署請求（OAC）
    ▼
S3 Bucket（完全私有，Block All Public Access）
    │
    ├─ Bucket Policy：只允許來自此 Distribution ARN 的 cloudfront.amazonaws.com
    └─ 直連 S3 URL → 403 Forbidden
```

---

## 你要做的事

| TODO | 資源 | 重點 |
|------|------|------|
| 1 | `aws_s3_bucket_public_access_block` | 四個選項全 true，確保 S3 完全私有 |
| 2 | `aws_s3_bucket_policy` | `cloudfront.amazonaws.com` Principal + `AWS:SourceArn` 條件 |
| 3 | `aws_cloudfront_origin_access_control` | `signing_behavior = "always"`, `signing_protocol = "sigv4"` |
| 4 | `aws_cloudfront_distribution` | Origin + OAC + Cache Behavior + custom_error_response |
| 5 | `aws_s3_object` × 2 | 上傳 index.html + error.html，設定 content_type + etag |

---

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

> ⚠️ `terraform apply` 建立 CloudFront Distribution 需要 **5-10 分鐘**，這是正常的。

---

## 驗證

### 1. 確認網站可以存取

```bash
CF_URL=$(terraform output -raw cloudfront_url)
echo "CloudFront URL: $CF_URL"

curl -I "$CF_URL"
# 期望：HTTP/2 200

curl -s "$CF_URL" | grep "CloudFront"
# 期望：出現 "CloudFront + S3 OAC" 字樣
```

### 2. 確認 S3 直連被拒絕（OAC 安全驗證）

```bash
S3_BUCKET=$(terraform output -raw s3_bucket_name)
S3_URL="https://${S3_BUCKET}.s3.amazonaws.com/index.html"

curl -I "$S3_URL"
# 期望：HTTP/1.1 403 Forbidden
# 這證明 S3 是私有的，只有 CloudFront 可以存取
```

### 3. 確認 404 頁面（custom_error_response 驗證）

```bash
CF_URL=$(terraform output -raw cloudfront_url)
curl -I "${CF_URL}/this-page-does-not-exist"
# 期望：HTTP/2 404（CloudFront 把 S3 的 403 轉成 404）
```

### 4. 測試 CloudFront Invalidation（更新內容後清除快取）

```bash
# 修改 www/index.html 後，重新上傳
terraform apply

# 建立 Invalidation 清除快取
DIST_ID=$(terraform output -raw distribution_id)
aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths "/*"

# 等待 Invalidation 完成（約 1-2 分鐘）
aws cloudfront wait invalidation-completed \
  --distribution-id "$DIST_ID" \
  --id $(aws cloudfront list-invalidations --distribution-id "$DIST_ID" \
         --query 'InvalidationList.Items[0].Id' --output text)

echo "快取已清除，重新存取 $CF_URL"
```

---

## 結束

```bash
terraform destroy -auto-approve
```

---

## 成本估算

| 資源 | 費用 |
|------|------|
| CloudFront（前 1TB 流量/月）| 免費 |
| CloudFront（超過後）| $0.0085/GB |
| S3 儲存（< 1MB）| < $0.001/月 |
| S3 請求（GET，CloudFront 快取命中不計）| < $0.001 |
| **合計（測試用途）** | **~$0** |

---

## 核心概念釐清

### OAI vs OAC

| | OAI（舊，不建議）| OAC（新，推薦）|
|--|---|---|
| 推出時間 | 2019 | 2022 |
| 支援 KMS 加密 S3 | 否 | 是 |
| 支援新 AWS 地區 | 部分 | 全部 |
| 設定方式 | IAM-like identity | 簽名協定（SigV4）|
| AWS 建議 | 停止使用 | 使用這個 |

### bucket_regional_domain_name 為何必要

```hcl
# 正確：OAC 要求
domain_name = aws_s3_bucket.website.bucket_regional_domain_name
# e.g. cf-lab-website-abcd1234.s3.us-east-1.amazonaws.com

# 錯誤：OAC 不支援舊格式
domain_name = aws_s3_bucket.website.bucket_domain_name
# e.g. cf-lab-website-abcd1234.s3.amazonaws.com
```

### 為何 custom_error_response 不可省略

```
情境：使用者存取 /not-found.html（不存在的檔案）

沒有 OAC 的情況（S3 靜態網站模式）：
S3 → 404 Not Found → CloudFront 顯示 404

有 OAC 的情況（私有 Bucket）：
S3 無法區分「你沒權限」和「檔案不存在」
→ 一律回傳 403 Access Denied
→ CloudFront 直接顯示 403（不友善）

正確處理（custom_error_response）：
S3 → 403 → CloudFront 看到 403
→ 依設定，回傳 /error.html 並將狀態碼改為 404
→ 使用者看到友善的 404 頁面
```

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `apply` 後很久還在 `Creating...` | CloudFront Distribution 建立本來就需要 5-10 分鐘，正常 |
| 存取 CloudFront URL 回傳 403 | Bucket Policy 可能還沒生效，等 1-2 分鐘；或 OAC 設定錯誤 |
| S3 直連回傳 200（不是 403） | `aws_s3_bucket_public_access_block` 沒有套用 |
| 更新 index.html 後網站沒變 | CloudFront 快取中，需要建立 Invalidation |
| `InvalidViewerCertificate` | 使用自訂域名時需要 ACM 憑證，本 lab 用預設憑證不會有此問題 |
| `BucketAlreadyExists` | Bucket name 全球唯一，random_id 應可避免，若衝突換 project 名稱 |
