# Lab 39：圖片處理微服務

> **場景**：使用者上傳圖片到 S3，系統自動處理並透過 CloudFront 分發。  
> **費用等級**：🟢 安全（< $0.10/次，S3 + Lambda + CloudFront 免費額度內）

---

## 學習目標

完成本 lab 後，你能夠：

- 設定 S3 → EventBridge 整合（`eventbridge = true`），與 Lab 09 的直接 Lambda 觸發做對比
- 撰寫 EventBridge Rule 的 `event_pattern`，過濾特定 bucket 的 Object Created 事件
- 使用 CloudFront OAC（Origin Access Control）保護私有 S3 Bucket，取代已棄用的 OAI
- 理解 `bucket_regional_domain_name` vs `bucket_domain_name` 的差異（OAC 必須用 regional）
- 設計最小權限 IAM Policy：Lambda 只讀 Input、只寫 Output，不允許跨 bucket 操作

---

## 架構

```
使用者 PUT image.jpg
      │
      ▼
S3 Input Bucket（eventbridge = true）
      │  AWS EventBridge S3 Event（Object Created）
      ▼
EventBridge Default Event Bus
      │
      ▼
EventBridge Rule（過濾 source=aws.s3、bucket=input）
      │
      ▼
Lambda: processor（複製檔案 + 產生 metadata.json）
      │  s3:PutObject
      ▼
S3 Output Bucket（完全私有）
      │
      ▼
CloudFront Distribution（OAC 簽章存取）
      │
      ▼
使用者透過 CloudFront URL 取得處理後的圖片
```

### 與 Lab 09 的關鍵差異（面試常考）

| 比較項目 | Lab 09：S3 直接觸發 | Lab 39：S3 → EventBridge |
|---------|-------------------|------------------------|
| 設定方式 | `aws_s3_bucket_notification` + Lambda ARN | `eventbridge = true` + Rule |
| 消費者數量 | 每種事件最多 1 個 Lambda | 無限（多個 Rule） |
| 過濾能力 | Prefix / Suffix | 複雜 Pattern（content-type、size、tag） |
| 事件歷史 | 無 | 有，可 Replay |
| 架構彈性 | 點對點 | 事件匯流排，可 fan-out |

---

## 你要做的事

| TODO | 資源 | 關鍵設定 |
|------|------|---------|
| 1 | S3 Input Bucket + Public Block + Notification | `eventbridge = true` |
| 2 | S3 Output Bucket + Public Block | 完全私有 |
| 3 | Lambda IAM Role + BasicExecution + S3 Inline Policy | 最小權限 |
| 4 | Lambda Function + EventBridge Permission | `principal = "events.amazonaws.com"` |
| 5 | EventBridge Rule + Target | `event_pattern` 過濾特定 bucket |
| 6 | CloudFront OAC + Distribution + S3 Bucket Policy | `bucket_regional_domain_name` |

---

## 指令

```bash
# 1. 複製 tfvars
cp terraform.tfvars.example terraform.tfvars

# 2. 初始化
terraform init

# 3. 格式化
terraform fmt

# 4. 驗證
terraform validate

# 5. 預覽
terraform plan

# 6. 部署（CloudFront 需 5-10 分鐘建立）
terraform apply -auto-approve
```

---

## 驗證方式

### 步驟 1：上傳測試圖片

```bash
# 取得 Input Bucket 名稱
INPUT_BUCKET=$(terraform output -raw input_bucket_name)

# 上傳任意圖片（或建立測試檔案）
echo "test image content" > /tmp/test-image.jpg
aws s3 cp /tmp/test-image.jpg s3://$INPUT_BUCKET/test-image.jpg
```

### 步驟 2：確認 Lambda 已處理

```bash
# 等待約 5 秒後確認 Output Bucket
OUTPUT_BUCKET=$(terraform output -raw output_bucket_name)
aws s3 ls s3://$OUTPUT_BUCKET/processed/ --recursive
```

預期看到：
```
2026-xx-xx xx:xx:xx    xxx test-image.jpg
2026-xx-xx xx:xx:xx    xxx test-image.jpg.metadata.json
```

### 步驟 3：透過 CloudFront 存取

```bash
# 取得 CloudFront Domain
CF_DOMAIN=$(terraform output -raw cloudfront_domain_name)

# 存取處理後的圖片（CloudFront 需先 Deploy 完成）
curl -I https://$CF_DOMAIN/processed/test-image.jpg
```

預期回傳 `HTTP/2 200`。

### 步驟 4：確認 EventBridge Rule 觸發次數

```bash
# 查詢 Rule 觸發統計（最近 1 小時）
terraform output eventbridge_events_command | bash
```

### 步驟 5：查看 Lambda 執行 Log

```bash
aws logs tail /aws/lambda/img-lab-processor --follow
```

---

## 結束

```bash
# 清空 Buckets（terraform destroy 無法刪除非空 bucket）
INPUT_BUCKET=$(terraform output -raw input_bucket_name)
OUTPUT_BUCKET=$(terraform output -raw output_bucket_name)
aws s3 rm s3://$INPUT_BUCKET --recursive
aws s3 rm s3://$OUTPUT_BUCKET --recursive

# 銷毀所有資源
terraform destroy -auto-approve
```

> **注意**：CloudFront Distribution 的 `destroy` 需要約 5-10 分鐘，因為需要等待 Disable 傳播到全球 Edge。

---

## 成本估算

| 資源 | 計費模式 | 預估費用 |
|------|---------|---------|
| S3 Input Bucket | PUT $0.005/1000 requests | < $0.01 |
| S3 Output Bucket | GET $0.0004/1000 requests | < $0.01 |
| Lambda | 前 1M 次免費，128MB | $0.00 |
| EventBridge | 前 1M event 免費 | $0.00 |
| CloudFront | 前 1TB/月 免費，1M requests 免費 | $0.00 |
| **合計** | | **< $0.05** |

---

## 架構決策紀錄（ADR）

### ADR-1：為什麼用 EventBridge 而不是直接 S3 → Lambda？

**決策**：使用 `eventbridge = true` + EventBridge Rule，而非 `aws_s3_bucket_notification` 直接指定 Lambda ARN。

**理由**：
- **Fan-out**：未來若需要同一個上傳事件同時觸發「縮圖 Lambda」和「病毒掃描 Lambda」，直接觸發模式每種事件類型只能有一個目標；EventBridge 可加入多個 Rule。
- **過濾彈性**：EventBridge Rule Pattern 支援 `prefix`、`suffix`、`content-type`、物件大小等複雜條件，直接觸發只支援前綴/後綴。
- **事件 Replay**：EventBridge 保留 24 小時事件歷史，Lambda 掛掉時可重放；直接觸發不支援。

**代價**：多一層 EventBridge 延遲（通常 < 1 秒），EventBridge Rule 有費用（前 1M events 免費，之後 $1/M）。

**結論**：對於需要擴展的生產架構，EventBridge 模式更優；對於只有單一消費者的簡單場景，Lab 09 的直接觸發更簡單。

---

### ADR-2：為什麼用 OAC 而不是 OAI？

**決策**：使用 CloudFront Origin Access Control（OAC），而非舊版的 Origin Access Identity（OAI）。

**理由**：
- **AWS 官方建議**：OAI 已被標記為 Legacy，新建資源應使用 OAC。
- **安全性更強**：OAC 使用 SigV4 簽章，每個請求都有時間戳記和內容 hash，不可偽造；OAI 使用固定的 IAM user。
- **Bucket Policy 更精確**：OAC 的 S3 Bucket Policy 可用 `AWS:SourceArn` 鎖定到特定 Distribution，避免同帳號其他 CloudFront Distribution 也能讀此 Bucket。

**代價**：OAC 設定稍複雜（需要 `origin_access_control_id` + Bucket Policy 兩步驟）。

**結論**：新建 CloudFront + S3 架構一律用 OAC。

---

### ADR-3：為什麼 Lambda 沒有使用 Pillow 圖片處理庫？

**決策**：Lambda 只做「複製 + 加 metadata」，不使用 Pillow 做實際縮圖。

**理由**：
- **架構 vs 影像處理**：本 lab 的學習重點是事件驅動架構（EventBridge、S3、CloudFront），而非影像處理演算法。
- **無外部依賴**：只用 boto3（Lambda runtime 內建），不需要打包 Layer 或 Lambda Container Image，降低設定複雜度。
- **易於替換**：`processor.py` 中的「模擬處理」區段有明確註解，生產環境可直接在此加入 Pillow resize 邏輯。

**代價**：輸出的圖片和輸入完全相同，只有 metadata 不同；無法展示實際縮圖效果。

**結論**：以架構為主，影像運算為輔。需要真實縮圖時，加入 Lambda Layer `pillow-heif` 即可。

---

## 可觀測性設計

| 觀測點 | 工具 | 查詢方式 |
|--------|------|---------|
| Lambda 執行成功/失敗 | CloudWatch Logs | `aws logs tail /aws/lambda/img-lab-processor` |
| Lambda 執行時間 | CloudWatch Metrics | `Duration` metric in `/aws/lambda/img-lab-processor` |
| EventBridge Rule 觸發次數 | CloudWatch Metrics | `TriggeredRules` in `AWS/Events` namespace |
| S3 PUT 請求數 | CloudWatch Metrics | `PutRequests` in `AWS/S3` per bucket |
| CloudFront 請求/錯誤 | CloudWatch Metrics | `Requests`, `4xxErrorRate`, `5xxErrorRate` |

**告警建議**：
```bash
# Lambda Error 告警
aws cloudwatch put-metric-alarm \
  --alarm-name "img-lab-lambda-errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --dimensions Name=FunctionName,Value=img-lab-processor \
  --period 60 --evaluation-periods 1 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --statistic Sum
```

---

## 卡關提示

| 症狀 | 原因 | 解法 |
|------|------|------|
| Lambda 沒有觸發 | EventBridge Rule 的 `event_pattern` 的 `bucket.name` 填錯 | 確認 `detail.bucket.name = [aws_s3_bucket.input.id]`（Array 格式） |
| Lambda 觸發但 Output Bucket 沒有檔案 | IAM Policy 的 `s3:PutObject` Resource 填錯 | 確認 Resource 是 `${aws_s3_bucket.output.arn}/*`（注意 `/*`） |
| CloudFront 回傳 403 | S3 Bucket Policy 的 `AWS:SourceArn` 未鎖定 Distribution ARN | 確認 Condition 中 `StringEquals["AWS:SourceArn"]` = `aws_cloudfront_distribution.main.arn` |
| Lambda Permission 設定錯誤 | `principal` 應為 `events.amazonaws.com` 而非 `s3.amazonaws.com` | Lab 09 是 S3 直接觸發用 `s3.amazonaws.com`，EventBridge 觸發用 `events.amazonaws.com` |
| `eventbridge = true` 但事件沒到 | S3 Bucket 的 EventBridge 設定和 Rule 在不同 region | 確認 Bucket 和 Rule 都在同一個 region |
| CloudFront destroy 卡住 | Distribution 仍在 Enabled 狀態，需先 Disable | `terraform destroy` 會自動 Disable，只是需要等待約 5 分鐘 |
| `bucket_regional_domain_name` 和 `bucket_domain_name` 差異 | OAC 必須用 regional domain，否則 CloudFront 無法正確簽章 | 確認 origin 使用 `aws_s3_bucket.output.bucket_regional_domain_name` |

---

## 面試故事

> 「我在 Lab 39 做了一個圖片處理微服務。使用者上傳圖片到 S3 Input Bucket，S3 透過 `eventbridge = true` 把事件送到 EventBridge，再用 Rule 過濾出特定 bucket 的 Object Created 事件觸發 Lambda。Lambda 把圖片複製到 Output Bucket 並產生 metadata.json。使用者透過 CloudFront 存取 Output Bucket，OAC 確保 S3 完全私有。
>
> 和直接 S3 → Lambda 觸發相比，走 EventBridge 的好處是可以 fan-out — 一個上傳事件可以同時觸發縮圖、病毒掃描、索引建立等多個下游，而且有事件歷史可以 replay。代價是多一層延遲，但通常 < 1 秒，對圖片處理場景完全可以接受。」

---

*建立於 2026-05-28*
