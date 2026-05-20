# AWS Terraform 學習路線圖（$48 預算版）

精簡版學習計畫，總預算控制在 **$48 / 月** 以內。

> **核心原則**：每個 lab 練習完，**立刻 `terraform destroy`**，把資源歸零。
> 真正燒錢的不是「開了什麼」，而是「忘了關什麼」。

---

## 預算總覽

| 項目 | 預估花費 | 說明 |
|------|----------|------|
| 階段 1（基礎設施）| ~$2 | 短時間開關 EC2、S3、VPC |
| 階段 2（資料層）| ~$3 | RDS 限制 24h 內 destroy |
| 階段 3（Serverless）| < $1 | 幾乎全在 Free Tier |
| 階段 4（容器化）| ~$5 | ECR + App Runner |
| 階段 5（Kubernetes）| ~$10-15 | EKS (短期測試) |
| 階段 6（監控/IAM）| < $2 | CloudWatch 低用量 |
| **緩衝（誤操作）** | ~$10 | 預留犯錯空間 |
| **總計** | **~$35-40** | 仍控制在 $48 上限內 |

---

## ❌ 已移除的高風險項目

| 項目 | 移除原因 | 替代方案 |
|------|----------|----------|
| NAT Gateway（階段 2 含在 VPC）| 開著就 $32/月，極易爆預算 | 改做 **public subnet only VPC**，不建 NAT |
| RDS 多日練習 | $15/月，忘關直接吃掉預算 | 單日內完成 + 立刻 destroy |
| ECS Fargate（12-14）| 服務開著計費，故障排查容易拖時間 | App Runner（用完即停）替代 |
| Elastic Beanstalk | 隱藏成本（EC2 + ELB）| 不需要 |

---

## 階段 1：基礎設施（第 1-2 週）

**預算：~$2**

| 編號 | 目錄 | 說明 | 預估花費 | 安全玩法 |
|------|------|------|----------|----------|
| 01 | `01-ec2-web-server` | EC2 + Security Group + SSH Key | < $1 | t3.micro Free Tier，2 小時內 destroy |
| 02 | `02-custom-vpc-public-only` | VPC + Public Subnet + IGW（**不含 NAT**）| $0 | VPC 本身免費 |
| 03 | `03-s3-static-website` | S3 靜態網站 | < $1 | S3 流量極低，可留著 |

**⚠️ 注意**：原 roadmap 的 `02-custom-vpc` 包含 NAT Gateway，這裡改成只做 public subnet。
NAT Gateway 等之後預算充足再學。

---

## 階段 2：資料層（第 3-4 週）

**預算：~$3**

| 編號 | 目錄 | 說明 | 預估花費 | 安全玩法 |
|------|------|------|----------|----------|
| 04 | `04-rds-postgres` | RDS PostgreSQL | ~$2 | **同一天 apply + destroy**，不過夜 |
| 05 | `05-dynamodb-basic` | DynamoDB（按需）| < $1 | 不用時幾乎 $0 |

**RDS 練習規則**：
- 用 `db.t3.micro`（Free Tier 750 hr/月，但儲存仍收費）
- 早上 apply，晚上 destroy
- 連 CloudWatch Logs 一起清掉

---

## 階段 3：Serverless（第 5-7 週）⭐ 最划算

**預算：< $1**

| 編號 | 目錄 | 說明 | 預估花費 |
|------|------|------|----------|
| 06 | `06-lambda-hello` | Lambda 基礎 | $0 |
| 07 | `07-lambda-api-gateway` | Lambda + API Gateway | $0 |
| 08 | `08-lambda-dynamodb-crud` | 完整 Serverless API | < $0.50 |
| 09 | `09-lambda-s3-trigger` | S3 事件觸發 | < $0.10 |

Lambda + API Gateway + DynamoDB 全在 Free Tier，幾乎免費。
**這一階段值得花最多時間練**。

---

## 階段 4：容器化（第 8-10 週）

**預算：~$5**

| 編號 | 目錄 | 說明 | 預估花費 | 備註 |
|------|------|------|----------|------|
| 10 | `10-ecr-repository` | ECR | < $1 | 儲存便宜，可留著 |
| 11 | `11-app-runner` | App Runner | ~$3-5 | **練完立刻 destroy** |

**移除**：原 12-14（ECS Fargate）。原因是 ECS 學習曲線陡，容易卡住，
卡住期間服務還在收費。等預算充足再回頭學。

---

## 階段 5：Kubernetes（第 12-14 週）⭐ 進階挑戰

**預算：~$10-15 (假設每次練習 2-4 小時)**

| 編號 | 目錄 | 說明 | 預估花費 | 安全玩法 |
|------|------|------|----------|----------|
| 12 | `12-eks-basic` | EKS Control Plane + Node Group | ~$5 | **用完立刻 destroy**，Control Plane 每小時 $0.1 |
| 13 | `13-eks-workloads` | Deployment + Service + Ingress | ~$5 | 練習 K8s 基本物件 |
| 14 | `14-eks-irsa` | IAM Roles for Service Accounts | < $1 | 學習 Pod 權限控管 |

**EKS 練習嚴格規則**：
1. **Control Plane 費用**：約 $0.10/小時。光建立就要 15-20 分鐘，請留足連續時間。
2. **Node Group**：使用 `t3.medium` 或 `t3.small`，數量維持 2 台。
3. **立刻毀滅**：練習結束後的 `terraform destroy` 是唯一活路。
4. **替代方案**：若預算極度吃緊，仍建議參考 `modules/aws-k3s` 用 EC2 跑 k3s。

---

## 階段 6：DevOps & 監控（第 15-16 週）

**預算：< $2**

| 編號 | 目錄 | 說明 | 預估花費 |
|------|------|------|----------|
| 19 | `19-cloudwatch-monitoring` | CloudWatch Alarms | < $1 |
| 21 | `21-iam-advanced` | IAM Policy 設計 | $0 |

**移除**：`20-secrets-manager`（每個 secret $0.40/月，多了就累積）。
改用 SSM Parameter Store（Free Tier）替代學習。

---

## 省錢三大原則

### 1. 用完就 destroy

每個 lab 結尾務必執行：
```bash
terraform destroy -auto-approve
```

### 2. 設定 AWS Budget 警報

在 AWS Console 設定：
- Budget = $48
- 達到 50% / 80% / 100% 各發一封 email
- 防止你忘記某個資源還在跑

### 3. 每天看一眼 Cost Explorer

養成習慣：每天早上花 30 秒看「昨天花了多少」。
異常會立刻發現（例如忘關的 NAT Gateway）。

---

## 練習順序建議

```
週 1-2:   01 → 02 → 03         （階段 1，~$2）
週 3-4:   05 → 04               （先做便宜的 DynamoDB，再做 RDS）
週 5-7:   06 → 07 → 08 → 09     （Serverless 馬拉松，幾乎免費）
週 8-10:  10 → 11               （容器化精簡版）
週 12-14: 12 → 13 → 14         （Kubernetes 進階挑戰）
週 15-16: 19 → 21               （收尾）
```

**16 週、$35-40 預估、$48 安全上限。**

---

## 推薦學習資源

- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- AWS Free Tier 細節: https://aws.amazon.com/free/
- AWS Pricing Calculator: https://calculator.aws/

---

## 未來擴展（等預算充足）

預算解放後再考慮：
- 階段 2 補做：完整 VPC + NAT Gateway
- 階段 4 補做：ECS Fargate + ALB + RDS 整合
- Remote State (S3 + DynamoDB)
- CI/CD (GitHub Actions + Terraform)
