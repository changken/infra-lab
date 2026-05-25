# AWS Terraform 學習路線圖 v2：深化實作

本 roadmap 針對**已通過 SAA / DVA / SOA 認證、完成 Labs 1-20** 的學習者設計。
目標是將理論知識轉化為可在面試中展示的實作能力。

> **核心原則**：每個 lab 練習完，**立刻 `terraform destroy`**。
> 真正燒錢的不是「開了什麼」，而是「忘了關什麼」。

---

## 學習策略：兩階段遞進

```
Phase 1：填空式單服務 labs（Labs 21-36）
  → 把沒實作過的 AWS 服務一個個摸熟，建立肌肉記憶

Phase 2：場景整合專案（Labs 37-43）
  → 組合多個服務，模擬真實工作負載，有東西可以 demo 和講故事
```

Phase 1 不跳過，是 Phase 2 的基礎。

---

## 總覽

| 階段 | 主題 | Labs | 難度 | 預估花費 | 主要認證覆蓋 |
|------|------|------|------|---------|------------|
| Phase 1-A | 訊息與事件 | 21-24 | ★★☆☆☆ | < $1 | DVA, SAA |
| Phase 1-B | CI/CD 自動化 | 25-27 | ★★★☆☆ | < $1 | DVA, SOA |
| Phase 1-C | 進階應用服務 | 28-32 | ★★☆☆☆ | ~$2 | SAA, DVA |
| Phase 1-D | 安全與合規 | 33-36 | ★★★☆☆ | < $1 | SOA, SAA |
| Phase 2 | 場景整合 | 37-43 | ★★★★☆ | ~$5 | 三張全覆蓋 |
| — | 緩衝（誤操作）| — | — | ~$5 | — |
| **合計** | | **23 labs** | | **~$15** | |

---

## ❌ 高風險項目（維持原則）

| 項目 | 風險 | 處置方式 |
|------|------|---------|
| ElastiCache | $0.017/hr，閒置照計費 | 同一天 apply + destroy |
| NAT Gateway | $0.045/hr = $32/月 | 不建，用 VPC Endpoint 替代 |
| CodePipeline | 每條 pipeline $1/月（執行免費）| lab 結束後 destroy |
| Route 53 Hosted Zone | $0.50/月/zone | lab 結束後立刻刪除 |

---

## Phase 1-A：訊息與事件驅動（Labs 21-24）

**難度：★★☆☆☆ ／ 預算：< $1 ／ 覆蓋：DVA, SAA**

| 編號 | 目錄 | 說明 | 費用 | 認證對應 |
|------|------|------|------|---------|
| 21 ✅ | `21-sqs-standard` | SQS Standard Queue + Dead Letter Queue + 可見性逾時 | $0 | DVA, SAA |
| 22 ✅ | `22-sns-topic` | SNS Topic + Email / SQS / Lambda 訂閱類型 | $0 | DVA, SAA |
| 23 ✅ | `23-eventbridge-rules` | EventBridge Rules + Schedule + 事件過濾 Pattern | $0 | DVA, SAA |
| 24 ✅ | `24-sns-sqs-fanout` | SNS → 多個 SQS 的 Fan-out Pattern | $0 | DVA, SAA |

### 學習重點
- SQS：Standard vs FIFO、Visibility Timeout、Dead Letter Queue、Long Polling
- SNS：Topic、Subscription Protocol（email / sqs / lambda / https）
- EventBridge：Rule Pattern、Schedule（rate / cron）、Target 設定
- Fan-out：一個事件廣播到多個消費者的解耦設計

### 取捨決策（面試常考）

| 情境 | 選擇 | 原因 |
|------|------|------|
| 需要確保訊息順序 | SQS FIFO | Standard 不保證順序 |
| 一個事件通知多個系統 | SNS fan-out to SQS | 解耦、各系統獨立消費 |
| 跨服務事件路由 | EventBridge | 支援複雜 Pattern 過濾、支援跨帳號 |
| 簡單背景工作佇列 | SQS | 最簡單，不需要 pub/sub |

---

## Phase 1-B：CI/CD 自動化（Labs 25-27）

**難度：★★★☆☆ ／ 預算：< $1 ／ 覆蓋：DVA, SOA**

| 編號 | 目錄 | 說明 | 費用 | 認證對應 |
|------|------|------|------|---------|
| 25 ✅ | `25-codebuild` | CodeBuild Project + buildspec.yml + ECR image build | < $0.10 | DVA, SOA |
| 26 ✅ | `26-codepipeline-ecs` | CodePipeline（Source → Build → Deploy to ECS）| ~$0.20 | DVA, SOA |
| 27 ✅ | `27-github-actions-oidc` | GitHub Actions + OIDC → AWS（零 Access Key）| $0 | DVA |

### 學習重點
- CodeBuild：buildspec.yml 結構、環境變數、ECR 推送權限
- CodePipeline：Stage、Action、Artifact Store（S3）、ECS Deploy Action
- OIDC：讓 GitHub Actions 直接 assume IAM Role，不用儲存 AWS credentials

### 取捨決策（面試常考）

| 情境 | 選擇 | 原因 |
|------|------|------|
| 純 AWS 生態系 | CodePipeline + CodeBuild | 原生整合，不需管 runner |
| 已有 GitHub 工作流 | GitHub Actions + OIDC | 更靈活，CI/CD 與程式碼同倉庫 |
| 需要儲存部署憑證 | 絕對不要 — 用 OIDC | Access Key 洩漏風險極高 |

---

## Phase 1-C：進階應用服務（Labs 28-32）

**難度：★★☆☆☆ ／ 預算：~$2 ／ 覆蓋：SAA, DVA**

| 編號 | 目錄 | 說明 | 費用 | 認證對應 |
|------|------|------|------|---------|
| 28 ✅ | `28-cloudfront-s3` | CloudFront Distribution + S3 Origin + OAC | < $0.10 | SAA |
| 29 ✅ | `29-route53-basic` | Route 53 Hosted Zone + A Record + Health Check | ~$0.50 | SAA |
| 30 ✅ | `30-elasticache-redis` | ElastiCache Redis（Cluster mode off）+ Lambda 測試 | ~$0.50 | SAA |
| 31 | `31-cognito-userpool` | Cognito User Pool + App Client + JWT 驗證 | $0 | DVA |
| 32 | `32-xray-lambda` | X-Ray + Lambda + API Gateway 分散式追蹤 | $0 | DVA |

### 學習重點
- CloudFront：OAC（Origin Access Control）取代舊版 OAI、Cache Behavior、TTL
- Route 53：Record Type、Routing Policy（Simple / Failover / Weighted）、Health Check
- ElastiCache：Node Type、Security Group（只開 6379 給 Lambda）、連線方式
- Cognito：User Pool vs Identity Pool、App Client、JWT Token 結構
- X-Ray：Sampling Rule、Service Map、Trace ID 傳遞

### 取捨決策（面試常考）

| 情境 | 選擇 | 原因 |
|------|------|------|
| S3 靜態網站加速 | CloudFront + OAC | S3 不要公開，透過 CloudFront 控制存取 |
| API 認證 | Cognito | 不要自己實作 JWT，讓 AWS 管 |
| 快取層 | ElastiCache Redis | DynamoDB DAX 只適合 DynamoDB，Redis 更通用 |
| 分散式追蹤 | X-Ray | 看到整條 request 鏈路的延遲和錯誤 |

---

## Phase 1-D：安全與合規（Labs 33-36）

**難度：★★★☆☆ ／ 預算：< $1 ／ 覆蓋：SOA, SAA**

| 編號 | 目錄 | 說明 | 費用 | 認證對應 |
|------|------|------|------|---------|
| 33 | `33-secrets-manager` | Secrets Manager + Lambda 自動輪換 + KMS 加密 | < $0.10 | DVA, SOA |
| 34 | `34-ssm-session-manager` | Systems Manager Session Manager（零 SSH）+ Patch Manager | $0 | SOA |
| 35 | `35-cloudtrail-config` | CloudTrail + Config Rules + SNS 合規告警 | < $0.50 | SOA, SAA |
| 36 | `36-asg-alb` | Auto Scaling Group + ALB + Scaling Policy（EC2 彈性擴展）| ~$0.30 | SAA |

### 學習重點
- Secrets Manager：Secret Rotation、KMS CMK、Lambda Rotation Function
- SSM Session Manager：不開 SSH port、IAM 控制 session、稽核紀錄
- CloudTrail：Management Events vs Data Events、Multi-region Trail
- Config：Managed Rule vs Custom Rule、Remediation Action
- ASG：Launch Template、Scaling Policy（Target Tracking / Step）、Lifecycle Hook

### 取捨決策（面試常考）

| 情境 | 選擇 | 原因 |
|------|------|------|
| 儲存資料庫密碼 | Secrets Manager（非 SSM）| 有自動輪換，SSM 無此功能 |
| 連線到 EC2 除錯 | SSM Session Manager | 不用 bastion host，有完整稽核 |
| 合規稽核 | Config + CloudTrail 搭配 | Config 看「現在是否合規」，CloudTrail 看「誰動了什麼」 |

---

## Phase 2：場景整合專案（Labs 37-43）

**難度：★★★★☆ ／ 預算：~$5 ／ 覆蓋：SAA + DVA + SOA 全覆蓋**

每個 lab 模擬真實公司場景，重點不只是「能跑」，而是 README 中必須有：
- 架構決策紀錄（ADR）：為什麼選這個服務而不是另一個
- 可觀測性設計：如何知道它壞了
- 成本估算：每月大概花多少

| 編號 | 場景 | 技術組合 | 費用 |
|------|------|---------|------|
| 37 | 電商訂單後端 | API GW → Lambda → SQS → Lambda → DynamoDB + SNS 通知 | < $0.50 |
| 38 | 自動化部署流水線 | GitHub Actions + OIDC → ECR → CodePipeline → ECS Blue/Green | ~$0.50 |
| 39 | 圖片處理微服務 | S3 → EventBridge → Lambda → CloudFront 分發 | < $0.10 |
| 40 | 多租戶 SaaS API | Cognito → API GW Authorizer → Lambda + 動態租戶隔離 | $0 |
| 41 | 可觀測性全棧 | X-Ray + CloudWatch Logs Insights + Dashboard + Synthetic | < $1 |
| 42 | 安全合規架構 | Config Rules + CloudTrail + GuardDuty + SNS 自動告警 | ~$1 |
| 43 | Terraform 模組化重構 | 抽取可重用 modules + S3 remote state + DynamoDB lock | < $0.10 |

### Lab 37：電商訂單後端

```
POST /orders
      │
      ▼
 API Gateway
      │
      ▼
  Lambda（驗證訂單）
      │
      ▼
   SQS Queue ◄── Dead Letter Queue（失敗訂單）
      │
      ▼
  Lambda（處理訂單）
      ├── DynamoDB（寫入訂單記錄）
      └── SNS（通知出貨系統 / Email）
```

**面試故事**：「我做過一個訂單系統，用 SQS 解耦驗證和處理，DLQ 處理失敗訂單，SNS fan-out 通知多個下游系統。這樣即使出貨系統暫時掛了，訂單也不會遺失。」

### Lab 38：自動化部署流水線

```
git push → GitHub Actions（OIDC）→ docker build → ECR push
                                                      │
                                              CodePipeline 偵測到新 image
                                                      │
                                              ECS Blue/Green Deploy
                                              （CodeDeploy 管理流量切換）
```

**面試故事**：「我設計過一個 CI/CD 流水線，用 OIDC 讓 GitHub Actions 直接 assume IAM Role，完全不存 Access Key。ECS Blue/Green 部署讓我可以在不停機的情況下更新服務。」

### Lab 43：Terraform 模組化重構

把 Labs 21-42 中重複的模式（VPC、Security Group、IAM Role）抽成可重用 module：

```
modules/
├── networking/     # VPC + Subnets + Security Groups
├── ecs-service/    # ECS Cluster + Task + Service + ALB
├── serverless-api/ # Lambda + API Gateway + IAM
└── observability/  # CloudWatch Dashboard + Alarms + SNS
```

加上 S3 remote state + DynamoDB lock，模擬團隊協作環境。

---

## 練習順序建議

```
Week 1:   21 → 22 → 23 → 24   （訊息事件，全免費，快速建立 event-driven 感）
Week 2:   25 → 26 → 27         （CI/CD，最有面試價值）
Week 3:   28 → 29 → 30         （網路層服務，注意 Route 53 / ElastiCache 費用）
Week 4:   31 → 32 → 33 → 34   （安全應用，全部偏便宜）
Week 5:   35 → 36               （合規稽核 + ASG）
Week 6-8: 37 → 38 → 39         （場景整合 Round 1）
Week 9-10: 40 → 41 → 42 → 43  （場景整合 Round 2，最終作品）
```

**10 週、~$15 預估。**

---

## 面試準備重點

完成每個 Phase 2 lab 後，用這三個問題自我測試：

1. **「你為什麼選這個架構？」** — 能說出 2-3 個替代方案和取捨理由
2. **「這個系統壞了你怎麼知道？」** — 有 CloudWatch Alarm / X-Ray / Dashboard
3. **「這個系統每個月花多少錢？」** — 能估算出合理數字

---

## 推薦學習資源

- AWS Well-Architected Framework: https://aws.amazon.com/architecture/well-architected/
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- AWS Pricing Calculator: https://calculator.aws/
- AWS Architecture Center: https://aws.amazon.com/architecture/

---

*建立於 2026-05-23，基於 Labs 1-20 完成後的學習路徑規劃*
