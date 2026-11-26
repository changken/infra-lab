# Lab 29: Route 53 Private Hosted Zone + Health Check + Routing Policy

> 用 Private Hosted Zone 建立 VPC 內部 DNS，並實作 Weighted Routing 和 HTTP Health Check。

**費用等級**：🟡 注意（~$0.50，Hosted Zone $0.50/月 + Health Check $0.50/月，apply 後立刻 destroy）

---

## 學習目標

- 理解 Public vs Private Hosted Zone 的差異和使用情境
- 掌握 A、CNAME 兩種記錄類型的差異（為何 CNAME 不能用於 Zone Apex）
- 設定 HTTP Health Check 並理解 `failure_threshold` 的意義
- 實作 Weighted Routing（A/B 測試場景）
- 理解 Failover Routing 的設計邏輯（面試常考）

---

## 架構

```
VPC（Private Hosted Zone 作用範圍）
    │
    ├── app.r53-lab.internal   → A Record → 10.0.1.100
    ├── api.r53-lab.internal   → CNAME   → app.r53-lab.internal
    │
    └── blue-green.r53-lab.internal（Weighted Routing）
            ├── primary   (weight=80) → 10.0.1.100
            └── secondary (weight=20) → 10.0.2.100

Route 53 Health Checker（全球 15 個節點）
    └── HTTPS example.com:443 /
            └── failure_threshold=3 → Unhealthy 才觸發 Failover
```

---

## 你要做的事

| TODO | 資源 | 重點 |
|------|------|------|
| 1 | `aws_route53_zone` | `vpc` block 讓 Zone 變 Private；`.internal` 慣例 |
| 2 | `aws_route53_record` × 2 | A Record + CNAME Record；理解兩者差異 |
| 3 | `aws_route53_health_check` | HTTPS 探測；`failure_threshold` + `request_interval` |
| 4 | `aws_route53_record` × 2 | Weighted Routing；`set_identifier` 區分同名記錄 |

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

---

## 驗證

### 1. 確認 Hosted Zone 建立成功

```bash
ZONE_ID=$(terraform output -raw zone_id)
ZONE_NAME=$(terraform output -raw zone_name)

aws route53 get-hosted-zone --id "$ZONE_ID" \
  --query '{Name: HostedZone.Name, Private: HostedZone.Config.PrivateZone}'
# 期望：{"Name": "r53-lab.internal.", "Private": true}
```

### 2. 列出所有 DNS 記錄

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --query 'ResourceRecordSets[*].{Name:Name, Type:Type, Records:ResourceRecords}'
# 期望：看到 app、api、blue-green（primary+secondary）的記錄
```

### 3. 確認 Weighted Records 的 weight 設定

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --query 'ResourceRecordSets[?Name==`blue-green.r53-lab.internal.`].{Name:Name,SetID:SetIdentifier,Weight:Weight}'
# 期望：primary=80, secondary=20
```

### 4. 確認 Health Check 狀態

```bash
HC_ID=$(terraform output -raw health_check_id)

# 查看 Health Check 設定
aws route53 get-health-check --health-check-id "$HC_ID" \
  --query 'HealthCheck.HealthCheckConfig.{FQDN:FullyQualifiedDomainName, Type:Type, Threshold:FailureThreshold}'

# 查看目前健康狀態（需等約 30 秒讓 Health Checker 完成初次探測）
aws route53 get-health-check-status --health-check-id "$HC_ID" \
  --query 'HealthCheckObservations[*].{Region:Region,Status:StatusReport.Status}' \
  --output table
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
| Route 53 Hosted Zone | $0.50/月（按天計費，1 小時 ≈ $0.0007）|
| Route 53 Health Check（HTTPS）| $0.50/月（按天計費，1 小時 ≈ $0.0007）|
| DNS 查詢（Private Zone，VPC 內）| 免費 |
| **合計（apply → destroy，約 1 小時）** | **~$0.001** |

> 儘管費用極低，仍建議練習完立刻 `terraform destroy`，養成習慣。

---

## 核心概念釐清

### Public vs Private Hosted Zone

| | Public Hosted Zone | Private Hosted Zone |
|--|---|---|
| 解析範圍 | 全球網際網路 | 指定 VPC 內部 |
| 是否需要真實域名 | 是（需要先購買/擁有域名）| 否（`.internal` 等任意名稱）|
| 常見用途 | 對外服務 | 微服務內部通訊、Service Discovery |
| Health Check 支援 | 完整支援 | 需配合 CloudWatch Alarm |

### CNAME vs ALIAS

```
CNAME：
  api.example.com → app.example.com  ✓
  example.com     → app.example.com  ✗ （Zone Apex 不支援 CNAME）
  收 DNS 查詢費

ALIAS（AWS 特有）：
  example.com → my-alb.us-east-1.elb.amazonaws.com  ✓ （Zone Apex 可用）
  不收 DNS 查詢費
  只能指向 AWS 資源（ALB, CloudFront, S3, 同 Zone 的 Route 53 record）
```

### Routing Policy 比較（面試高頻）

| Policy | 使用情境 | 需要 Health Check？|
|--------|---------|------------------|
| Simple | 最基本，一個域名一個 IP | 否 |
| Weighted | A/B 測試、漸進式部署 | 可選（不健康的不算在分母）|
| Failover | 主備切換（Active-Passive）| 是（Primary 掛了切 Secondary）|
| Latency | Multi-region，回傳延遲最低的 Region | 可選 |
| Geolocation | 台灣用戶走亞太 Region | 可選 |

### Failover Routing 設計（面試常考）

```hcl
# Primary（健康時接流量）
resource "aws_route53_record" "primary" {
  ...
  failover_routing_policy { type = "PRIMARY" }
  health_check_id = aws_route53_health_check.main.id  # 必須綁 Health Check
}

# Secondary（Primary 不健康時接流量）
resource "aws_route53_record" "secondary" {
  ...
  failover_routing_policy { type = "SECONDARY" }
  # Secondary 不需要 Health Check（Primary 掛了它就接）
}
```

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `VPCAssociationAlreadyExists` | 這個 VPC 已被另一個同名 Private Zone 關聯，換 `project` 名稱或先 destroy 舊 zone |
| Health Check 狀態一直是 `Unknown` | 等 30-60 秒讓 Health Checker 初次探測完成 |
| `InvalidChangeBatch` | CNAME 指向的目標域名格式錯誤（必須是 FQDN，結尾加不加 `.` 都行）|
| Weighted Record apply 失敗 | `set_identifier` 在同一個 zone 內的同名 record 中必須唯一 |
| `ConflictingRRSET` | 同名記錄已有 Simple routing，不能混用 Weighted；先刪再建 |
