# AWS Terraform 學習路線圖

完整的 AWS + Terraform 學習計畫，預算控制在 **$48 / 月** 以內，預計約 15 週完成。

> **核心原則**：每個 lab 練習完，**立刻 `terraform destroy`**，把資源歸零。
> 真正燒錢的不是「開了什麼」，而是「忘了關什麼」。

---

## 總覽

### 學習時程與難度

| 階段 | 主題 | 週數 | 難度 | 預估花費 |
|------|------|------|------|---------|
| 1 | 基礎設施 | 第 1-2 週 | ★☆☆☆☆ | ~$2 |
| 2 | 資料層 | 第 3-4 週 | ★★☆☆☆ | ~$3 |
| 3 | Serverless | 第 5-7 週 | ★★☆☆☆ | < $1 |
| 4 | 容器化 | 第 8-11 週 | ★★★☆☆ | ~$2 |
| 5 | Kubernetes | 第 12-13 週 | ★★★★☆ | ~$1.50 |
| 6 | DevOps & 監控 | 第 14-15 週 | ★★★☆☆ | < $2 |
| — | 緩衝（誤操作）| — | — | ~$10 |
| **合計** | | **15 週** | | **~$22** |

### 難度曲線

```
難度
  ▲
★★★★│                        ┌──────┐  ┌──┐
★★★ │              ┌──────┐  │  K8s │  │監控│
★★  │    ┌──┐  ┌──┐│Server│  │      │  │IAM │
★   │┌──┐│  │  │  ││less  │  │      │  │    │
    ││基礎│DB│  │  ││      │  │      │  │    │
    └┴──┴┴──┴──┴──┴┴──────┴──┴──────┴──┴────┴─▶ 週
      1-2  3-4   5-7     8-11    12-13    14-15
```

---

## ❌ 高風險項目（已移除或限制）

| 項目 | 風險 | 處置方式 |
|------|------|---------|
| NAT Gateway | $32/月固定費，開著就燒錢 | 改做 public subnet only VPC |
| RDS 長時間運行 | $15/月，忘關直接吃掉預算 | 同一天 apply + destroy |
| EKS 持續運行 | Control Plane $0.10/hr = $72/月 | 改為「一日 Sprint」，當天建當天砍 |
| ALB 長時間掛著 | $16/月 | 做完 lab 立刻 destroy |
| Elastic Beanstalk | 隱藏 EC2 + ELB 費用 | 不需要，ECS/App Runner 替代 |

---

## 階段 1：基礎設施（第 1-2 週）

**難度：★☆☆☆☆ ／ 預算：~$2**

| 編號 | 目錄 | 說明 | 預估花費 | 安全玩法 |
|------|------|------|---------|---------|
| 01 ✅ | `01-ec2-web-server` | EC2 + Security Group + SSH Key | < $1 | t3.micro，2 小時內 destroy |
| 02 ✅ | `02-custom-vpc-public-only` | VPC + Public Subnet + IGW（不含 NAT）| $0 | VPC 本身免費 |
| 03 ✅ | `03-s3-static-website` | S3 靜態網站 | < $1 | 流量極低，可留著 |

### 學習重點
- Terraform 基本語法：provider, resource, variable, output
- AWS 網路基礎：VPC、Subnet、Route Table、Internet Gateway
- S3：Bucket Policy、Public Access Block、靜態網站托管

### 完成後您將能夠
- 部署 EC2 並設定 Security Group 控制流量
- 設計 VPC 網路架構（不含 NAT 的公有子網路）
- 用 S3 托管靜態網站

---

## 階段 2：資料層（第 3-4 週）

**難度：★★☆☆☆ ／ 預算：~$3**

| 編號 | 目錄 | 說明 | 預估花費 | 安全玩法 |
|------|------|------|---------|---------|
| 04 ✅ | `04-rds-postgres` | RDS PostgreSQL | ~$2 | **同一天 apply + destroy**，不過夜 |
| 05 ✅ | `05-dynamodb-basic` | DynamoDB + GSI + TTL | < $1 | PAY_PER_REQUEST，幾乎 $0 |

### 學習重點
- RDS：DB Subnet Group、Security Group、`skip_final_snapshot`
- DynamoDB：Partition Key、Sort Key、GSI、TTL、DynamoDB JSON 格式
- IAM：最小權限原則，Resource 鎖定到特定 ARN

### 完成後您將能夠
- 建立受管 PostgreSQL 資料庫並設定網路隔離
- 設計 DynamoDB NoSQL 資料模型（含 GSI 查詢）

---

## 階段 3：Serverless（第 5-7 週）⭐ 最划算

**難度：★★☆☆☆ ／ 預算：< $1**

| 編號 | 目錄 | 說明 | 預估花費 |
|------|------|------|---------|
| 06 ✅ | `06-lambda-hello` | Lambda 基礎 + IAM Role | $0 |
| 07 ✅ | `07-lambda-api-gateway` | Lambda + API Gateway HTTP API | $0 |
| 08 ✅ | `08-lambda-dynamodb-crud` | 完整 Serverless CRUD API | < $0.50 |
| 09 ✅ | `09-lambda-s3-trigger` | S3 事件觸發 Lambda | < $0.10 |

Lambda + API Gateway + DynamoDB 全在 Free Tier，**這一階段值得花最多時間練**。

### 學習重點
- Lambda：`assume_role_policy`、handler 格式、`source_code_hash`
- API Gateway v2：Integration、Route、`$default` Stage、`auto_deploy`
- S3 Notification：`principal = "s3.amazonaws.com"`、`depends_on` 的必要性
- IAM：`aws_iam_role_policy` 自訂 Policy vs 內建 Policy

### 完成後您將能夠
- 建立無伺服器 REST API（Lambda + API Gateway）
- 實作事件驅動架構（S3 觸發 Lambda）
- 整合 Lambda 與 DynamoDB 做完整 CRUD

---

## 階段 4：容器化（第 8-11 週）

**難度：★★★☆☆ ／ 預算：~$2**

| 編號 | 目錄 | 說明 | 預估花費 | 安全玩法 |
|------|------|------|---------|---------|
| 10 | `10-ecr-repository` | ECR + Docker image push | < $0.10 | 儲存便宜，可留著 |
| 11 | `11-ecs-fargate` | ECS Fargate（無 ALB，公網 IP）| ~$0.10 | 理解 Cluster/Task/Service 概念 |
| 12 | `12-ecs-fargate-alb` | ECS Fargate + ALB（完整生產架構）| ~$0.30 | **2 小時內 destroy**，ALB 開著計費 |
| 13 | `13-app-runner` | App Runner（對比 ECS）| ~$0.50 | Scale to zero，相對安全 |
| 14 | `14-ecs-fargate-rds` | ECS + RDS 整合（有狀態服務）| ~$0.80 | **同一天完成**，RDS 費用較高 |

### ECS vs App Runner

| | ECS Fargate | App Runner |
|--|------------|-----------|
| 設定複雜度 | 高（Cluster + Task + Service + ALB）| 低（只需 image URL）|
| 控制彈性 | 高（VPC、port、完全自訂）| 低（AWS 管理大部分）|
| 費用模式 | 按 vCPU/記憶體時間計費 | 按請求計費（idle 時更省）|
| 適合場景 | 生產環境、複雜需求 | 快速部署、流量不穩定 |

### 學習重點
- ECR：Lifecycle Policy、image tag 管理
- ECS：Cluster、Task Definition、Service、`desired_count`
- ALB：Target Group、Listener、Health Check
- Secrets Manager / SSM Parameter Store：容器環境變數安全管理

### 完成後您將能夠
- 建立完整 ECS Fargate 服務架構（含 ALB）
- 整合容器服務與 RDS 資料庫
- 比較 ECS 和 App Runner 的適用場景

---

## 階段 5：Kubernetes（第 12-13 週）⭐ 一日 Sprint

**難度：★★★★☆ ／ 預算：~$1.50**

> **EKS 費用真相**：Control Plane $0.10/hr + t3.small $0.023/hr
> 一次 4-6 小時 lab ≈ **$0.60**，完全可控。
> 危險只在「忘記 destroy」。

| 編號 | 目錄 | 說明 | 預估花費 |
|------|------|------|---------|
| 15 | `15-eks-cluster` | EKS Control Plane + Managed Node Group | ~$0.50 |
| 16 | `16-eks-workloads` | Deployment + Service + Ingress | ~$0.50 |
| 17 | `17-eks-irsa` | IAM Roles for Service Accounts（IRSA）| ~$0.30 |
| 18 | `18-eks-helm` | Helm Provider + 部署應用 | ~$0.20 |

### EKS 一日 Sprint 規則

1. **排整塊時間**：EKS 建立需要 15-20 分鐘，Lab 15-18 建議一次連著完成
2. **Node 配置**：1 台 `t3.small`，足夠跑練習用的 workload
3. **當天 destroy**：Session 結束前執行 destroy，絕不過夜
4. **替代方案**：若當天時間不夠，用 `modules/aws-k3s`（EC2 跑 k3s，~$0.02/hr）學 K8s 概念

### 學習重點
- EKS：OIDC Provider、Managed Node Group、kubeconfig 設定
- K8s 基本物件：Deployment、Service、Ingress
- IRSA：讓 Pod 安全存取 AWS 資源（不用 hardcode credentials）
- Helm：Chart、Values、Terraform `helm_release` resource

### 完成後您將能夠
- 建立並管理 EKS Kubernetes 叢集
- 部署容器化應用到 K8s
- 設定 Pod 存取 AWS 資源的正確方式（IRSA）
- 用 Helm 管理 K8s 應用部署

---

## 階段 6：DevOps & 監控（第 14-15 週）

**難度：★★★☆☆ ／ 預算：< $2**

| 編號 | 目錄 | 說明 | 預估花費 |
|------|------|------|---------|
| 19 | `19-cloudwatch-monitoring` | CloudWatch Metrics + Alarms + Dashboard | < $1 |
| 20 | `20-iam-advanced` | IAM Policy 設計 + 最小權限實踐 | $0 |

### 學習重點
- CloudWatch：自訂 Metrics、Alarm、SNS 通知、Dashboard
- IAM：Policy 條件（Condition）、Permission Boundary、跨帳號存取
- SSM Parameter Store：免費的 Secrets 替代方案

### 完成後您將能夠
- 建立完整監控告警系統
- 設計符合最小權限原則的 IAM Policy

---

## 服務選擇決策樹

```
你想部署什麼類型的應用？
│
├─► 靜態網站（HTML/JS/CSS）
│   └─► S3 + CloudFront ✅（Lab 03）
│
├─► 簡單 API / 函數 / 事件處理
│   └─► Lambda + API Gateway ✅（Lab 06-09）
│
├─► 容器化應用
│   │
│   ├─► 想要最簡單的部署體驗？
│   │   └─► App Runner ✅（Lab 13）
│   │
│   ├─► 需要 VPC 隔離、完整控制？
│   │   ├─► ECS Fargate（無 ALB）✅（Lab 11）
│   │   └─► ECS Fargate + ALB ✅（Lab 12）
│   │
│   ├─► 需要 Database？
│   │   └─► ECS Fargate + RDS ✅（Lab 14）
│   │
│   └─► 需要 Kubernetes？
│       └─► EKS ✅（Lab 15-18）
│
├─► 傳統應用（非容器）
│   └─► EC2 ✅（Lab 01）
│
└─► 需要資料庫
    ├─► 關聯式（SQL）→ RDS PostgreSQL ✅（Lab 04）
    └─► 非關聯式（NoSQL）→ DynamoDB ✅（Lab 05）
```

---

## 省錢三大原則

### 1. 用完就 destroy

```bash
terraform destroy -auto-approve
```

### 2. 設定 AWS Budget 警報

- Budget = $48
- 達到 50% / 80% / 100% 各發一封 email
- 防止忘記某個資源還在跑

### 3. 每天看一眼 Cost Explorer

養成習慣：每天早上 30 秒看「昨天花了多少」。
異常立刻發現（例如忘關的 ALB 或 RDS）。

---

## 練習順序建議

```
週 1-2:   01 → 02 → 03              （基礎，~$2）
週 3-4:   05 → 04                    （先便宜的 DynamoDB，再 RDS）
週 5-7:   06 → 07 → 08 → 09          （Serverless 馬拉松，幾乎免費）
週 8-11:  10 → 11 → 12 → 13 → 14    （容器化完整版）
週 12-13: 15 → 16 → 17 → 18          （EKS 一日 Sprint，排整塊時間）
週 14-15: 19 → 20                    （收尾）
```

**15 週、~$22 預估、$48 安全上限。**

---

## 推薦學習資源

- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- AWS 架構中心: https://aws.amazon.com/architecture/
- HashiCorp Learn: https://learn.hashicorp.com/terraform
- AWS Free Tier 細節: https://aws.amazon.com/free/
- AWS Pricing Calculator: https://calculator.aws/

---

## 未來擴展（完成以上後）

- 階段 2 補做：完整 VPC + NAT Gateway（預算充足後）
- Remote State：S3 + DynamoDB 管理 tfstate
- Terraform Workspaces / Terragrunt：多環境管理
- CI/CD：GitHub Actions + Terraform 自動化部署
- Policy as Code：Sentinel / OPA
- EKS 進階：Cluster Autoscaler、HPA、Karpenter
