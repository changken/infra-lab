# AI Agent 協作指南

本文檔為 AI 助手（Claude、Gemini 等）提供專案背景與協作規範。
Claude Code 透過 `CLAUDE.md`（symlink）自動載入，Gemini CLI 透過 `GEMINI.md`（symlink）自動載入。

## 專案概覽

**專案名稱**: Terraform AWS Labs
**專案目標**: 透過填空式實作練習學習 Terraform 和 AWS，從基礎到進階逐步建立能力
**學習方式**: 每個 lab 獨立運作，練習完立刻 `terraform destroy`
**預算上限**: $48 / 月（詳見 `docs/roadmap.md`）
**語言**: 主要文件使用繁體中文，程式碼使用英文

## 目錄結構

```
terraform/
├── agents.md              # AI 協作指南（CLAUDE.md / GEMINI.md 為 symlink）
├── CLAUDE.md              # → agents.md（Claude Code 自動載入）
├── GEMINI.md              # → agents.md（Gemini CLI 自動載入）
├── docs/
│   └── roadmap.md         # 完整學習路線圖（含費用估算）
├── labs/                  # 練習專案（按編號順序）
│   ├── 01-ec2-web-server/         ✅ 完成
│   ├── 02-custom-vpc-public-only/ ✅ 完成
│   ├── 03-s3-static-website/      ✅ 完成
│   ├── 04-rds-postgres/           ✅ 完成
│   ├── 05-dynamodb-basic/         ✅ 完成
│   ├── 06-lambda-hello/           ✅ 完成
│   ├── 07-lambda-api-gateway/     ✅ 完成
│   ├── 08-lambda-dynamodb-crud/   ✅ 完成
│   ├── 09-lambda-s3-trigger/      ✅ 完成
│   ├── 10-ecr-repository/         ✅ 完成
│   ├── 11-ecs-fargate/            ✅ 完成
│   ├── 12-ecs-fargate-alb/        ✅ 完成
│   ├── 13-app-runner/             ✅ 完成
│   ├── 13-ecs-express-gateway/    ✅ 完成
│   ├── 14-ecs-fargate-rds/        ✅ 完成
│   ├── 15-eks-cluster/            ✅ 完成
│   ├── 16-eks-workloads/          ✅ 完成
│   ├── 17-eks-irsa/               ✅ 完成
│   ├── 18-eks-helm/               ✅ 完成
│   ├── 19-cloudwatch-monitoring/  ✅ 完成
│   ├── 20-iam-advanced/           ✅ 完成
│   ├── 21-sqs-standard/           ✅ 完成
│   ├── 22-sns-topic/              ✅ 完成
│   ├── 23-eventbridge-rules/      ✅ 完成
│   ├── 24-sns-sqs-fanout/         ✅ 完成
│   ├── 25-codebuild/              ✅ 完成
│   ├── 26-codepipeline-ecs/       ✅ 完成
│   ├── 27-github-actions-oidc/    ✅ 完成
│   └── 28-cloudfront-s3/          ✅ 完成
└── modules/               # 可重用模組（參考用）
    ├── aws-k3s/           # 輕量 K8s（EKS 替代方案）
    ├── aws-windows-spot/
    └── azure-k3s/
```

## 學習路線（共 15+ 週）

完整路線圖請參考 `docs/roadmap.md`（核心）與 `docs/roadmap-v2.md`（進階），共分為多個階段：

| 階段 | 主題 | 週數 | 難度 | 預算 |
|------|------|------|------|------|
| 1 | 基礎設施（EC2, VPC, S3）| 第 1-2 週 | ★☆☆☆☆ | ~$2 |
| 2 | 資料層（RDS, DynamoDB）| 第 3-4 週 | ★★☆☆☆ | ~$3 |
| 3 | Serverless（Lambda, API GW）| 第 5-7 週 | ★★☆☆☆ | < $1 |
| 4 | 容器化（ECR, ECS, App Runner）| 第 8-11 週 | ★★★☆☆ | ~$2 |
| 5 | Kubernetes（EKS）| 第 12-13 週 | ★★★★☆ | ~$1.50 |
| 6 | DevOps & 監控（CloudWatch, IAM）| 第 14-15 週 | ★★★☆☆ | < $2 |
| Phase 1-A | 訊息與事件（SQS, SNS, EventBridge）| 實作中 | ★★☆☆☆ | < $1 |

## AI 協作規範

### 核心原則

1. **填空式設計**：新 lab 骨架應提供 TODO 提示，讓使用者自行填寫，而非給出完整答案
2. **學習導向**：優先考慮可讀性和教育價值，而非極致優化
3. **程式碼美化**：引導用戶在 commit 前執行 `terraform fmt`，維持專案整潔
4. **成本意識**：主動提醒費用，每個 lab README 必須包含費用估算
5. **獨立性**：每個 lab 獨立運作，`terraform destroy` 後不留殘存資源
6. **漸進式**：按路線圖順序進行，避免跳躍式學習

### Lab 骨架結構

每個 lab 目錄應包含：

```
xx-lab-name/
├── terraform.tf           # Provider + Terraform 版本
├── variables.tf           # 輸入變數
├── locals.tf              # 區域變數（common_tags 等）
├── main.tf                # 主要資源（含 TODO 提示）
├── outputs.tf             # 輸出值（部分 TODO）
├── terraform.tfvars.example
├── .gitignore             # 含 *.tfvars, *.tfstate, src/*.zip 等
├── .terraform.lock.hcl    # ✅ 應提交至 Git，鎖定 Provider 版本
└── README.md              # 含學習目標、架構、指令、費用、動態驗證
```

### main.tf TODO 格式

```hcl
#--------------------------------------------------------------
# TODO N: 資源說明
#--------------------------------------------------------------
# 文件: https://registry.terraform.io/providers/...
#
# 需要設定：
#   key1 = value1    # 說明
#   key2 = value2
#
# ⚠️ 注意：特別容易出錯的地方

resource "aws_xxx" "name" {
  # TODO
}
```

### README.md 必要章節

1. 標題 + 一句話說明 + 費用等級
2. 學習目標（bulleted list）
3. 架構圖（ASCII）
4. 你要做的事（TODO 對應表）
5. 指令（cp tfvars → init → fmt → validate → plan → apply）
6. **驗證方式 (包含動態驗證腳本或指令，如 curl/aws cli)**
7. 結束（`terraform destroy -auto-approve`）
8. 成本（精確估算）
9. 卡關提示（症狀 → 原因 對應表）

### 命名規範

- **資源名稱**: `snake_case`，例如 `aws_instance.web_server`
- **變數名稱**: 描述性，例如 `instance_type` 而非 `type`
- **Tags**: 統一用 `local.common_tags`，結構為 `Project / Environment / ManagedBy`
- **Lab 目錄**: `NN-kebab-case`，例如 `10-ecr-repository`

### 成本警示等級

| 等級 | 費用 | 資源範例 | 處置 |
|------|------|---------|------|
| 🟢 安全 | < $0.10/次 | Lambda, DynamoDB, S3 | 可隨時操作 |
| 🟡 注意 | $0.10-1/次 | ECS Fargate, ECR | 練完當天 destroy |
| 🔴 危險 | > $1/hr | RDS, ALB, EKS | 同一天完成，不過夜 |

**高費用資源特別提醒**：
- NAT Gateway：$0.045/hr = $32/月，**絕對不建**
- RDS：$0.017-0.02/hr，同一天 apply + destroy
- ALB：$0.008/hr + LCU，2 小時內 destroy
- EKS Control Plane：$0.10/hr，一日 Sprint 當天砍

## 協助方式建議

### 建立新 Lab

1. 確認編號符合路線圖（`docs/roadmap.md`）
2. 採用填空式骨架，TODO 提示要夠清楚但不要直接給答案
3. 費用估算與**驗證腳本 (如：`curl http://...`)** 放在 README 顯眼位置
4. `.gitignore` 必須包含 `*.tfvars`、`*.tfstate`、`src/*.zip`
5. 提醒使用者 `.terraform.lock.hcl` 需要進入版本控制

### 除錯協助

1. 確認 Terraform 版本 `>= 1.9`
2. 建議執行 `terraform fmt` → `terraform validate` → `terraform plan`
3. 注意 IAM 權限、Security Group 規則
4. `*.tfstate` 不應提交到版本控制

### 常見卡關模式

| 症狀 | 常見原因 |
|------|---------|
| `attribute not defined` | DynamoDB attribute block 缺少 GSI/LSI 用到的欄位 |
| Lambda invoke 失敗 | `aws_lambda_permission` 沒設或 `principal` 錯誤 |
| S3 notification 不觸發 | `aws_s3_bucket_notification` 缺少 `depends_on = [aws_lambda_permission.xxx]` |
| RDS apply 卡住 | 正常，RDS 啟動需要 5-10 分鐘 |
| destroy 失敗 | S3 bucket 非空，先 `aws s3 rm s3://bucket --recursive` |
| `assume_role_policy` 錯誤 | `Principal.Service` 必須是 `lambda.amazonaws.com` 等，不能是 ARN |

## 安全最佳實踐

1. **不要硬編碼密鑰**：密碼放 `terraform.tfvars`（已加入 `.gitignore`）
2. **最小權限原則**：IAM Policy 的 `Resource` 鎖定到特定 ARN，不用 `"*"`
3. **敏感輸出**：密碼相關 output 加 `sensitive = true`
4. **Security Group**：預設拒絕，明確允許需要的 port

## 服務選擇決策樹

```
應用類型？
├─► 靜態網站          → S3（Lab 03）
├─► 函數 / API        → Lambda + API Gateway（Lab 06-08）
├─► 事件處理          → Lambda + S3/SNS/SQS（Lab 09）
├─► 容器（簡單）      → App Runner（Lab 13）
├─► 容器（需要控制）  → ECS Fargate（Lab 11-12）
├─► 容器 + DB         → ECS + RDS（Lab 14）
├─► Kubernetes        → EKS（Lab 15-18）
├─► 傳統應用          → EC2（Lab 01）
├─► SQL 資料庫        → RDS PostgreSQL（Lab 04）
└─► NoSQL 資料庫      → DynamoDB（Lab 05）
```

## 參考資源

- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- AWS Pricing Calculator: https://calculator.aws/
- AWS Free Tier: https://aws.amazon.com/free/
- HashiCorp Learn: https://learn.hashicorp.com/terraform

## 更新記錄

- 2026-05-21: 強化程式碼美化 (fmt)、Provider 鎖定 (lock file) 與動態驗證標準
- 2026-05-21: 更新目錄結構（labs/ 架構）、學習路線（15 週）、新增容器化和 EKS 內容
- 2026-02-03: 初始版本建立
