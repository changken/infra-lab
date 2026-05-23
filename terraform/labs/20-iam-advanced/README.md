# Lab 20: IAM Advanced（最終章）

用四個進階 IAM 概念打造一個安全的 Developer Role：Region 限制、ABAC 標籤控制、Explicit Deny 和 Permission Boundary。
**費用等級 🟢 安全** — IAM 完全免費，S3 空 bucket < $0.01/月。

## 學習目標

- `aws:RequestedRegion` condition key：讓 Allow 只在特定 region 生效
- **ABAC**（Attribute-Based Access Control）：`aws:ResourceTag/<key>` 根據 tag 動態決定存取權
- **Explicit Deny**：`Effect = "Deny"` 永遠勝過 Allow，防止特權昇級
- **Permission Boundary**：`permissions_boundary` 屬性設定 Role 的最大有效權限上限
- `aws iam simulate-principal-policy`：不執行實際操作就能驗證 IAM 效果

## IAM 評估邏輯（必讀）

```
請求 → 有 Explicit Deny？→ 是 → 拒絕（結束）
           ↓ 否
       有 Allow 且在 Boundary 內？→ 是 → 允許
           ↓ 否
       拒絕（Implicit Deny）
```

**有效權限公式：**
```
有效權限 = (身份政策 Allow) ∩ (Permission Boundary Allow) - (任何 Explicit Deny)
```

## 架構：Developer Role

```
aws_iam_role.developer（permissions_boundary → permission_boundary policy）
    │
    ├── aws_iam_policy.allow_ec2_read_regional
    │       Action: ec2:Describe*
    │       Condition: aws:RequestedRegion = us-east-1
    │
    ├── aws_iam_policy.allow_s3_tagged  （ABAC）
    │       Action: s3:ListBucket / s3:GetObject / s3:PutObject
    │       Condition: aws:ResourceTag/Team = "dev"
    │
    └── aws_iam_policy.deny_privilege_escalation
            Effect: Deny（iam:CreateRole / iam:AttachRolePolicy ...）
            ← 無論其他 policy 給什麼，這個 Deny 永遠生效

資源層面：
    aws_s3_bucket.dev  （Team=dev）  ← ABAC 允許
    aws_s3_bucket.ops  （Team=ops）  ← ABAC 拒絕
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_iam_policy.allow_ec2_read_regional` | Condition: `aws:RequestedRegion` |
| 2 | `aws_iam_policy.allow_s3_tagged` | Condition: `aws:ResourceTag/Team = "dev"`（ABAC）|
| 3 | `aws_iam_policy.deny_privilege_escalation` | `Effect = "Deny"` on IAM write actions |
| 4 | `aws_iam_policy.permission_boundary` | 複合 boundary：EC2 read + S3 read + Deny IAM |
| 5 | `aws_iam_role.developer` | `permissions_boundary` 屬性綁定 boundary policy |

已預填：data source（caller identity）、兩個 S3 bucket（不同 Team tag）、三個 policy attachment

## 指令

### Step 1：填寫 TODOs 並建立資源

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：9 to add
terraform apply
```

### Step 2：用 Policy Simulator 驗證（無需實際執行操作）

```bash
# ✅ 預期：ALLOWED — EC2 read 在 us-east-1（身份政策允許 + Boundary 允許）
terraform output simulate_allow_command
# 複製並執行，看 EvalDecision = "allowed"

# ❌ 預期：DENIED — IAM write（Explicit Deny 生效）
terraform output simulate_deny_command
# 複製並執行，看 EvalDecision = "explicitDeny"

# ❌ 預期：DENIED — EC2 read 在 eu-west-1（Boundary 限制 region）
terraform output simulate_boundary_command
# 複製並執行，看 EvalDecision = "implicitDeny" 或 "explicitDeny"
```

**預期輸出格式：**
```json
{
    "EvaluationResults": [
        {
            "EvalActionName": "ec2:DescribeInstances",
            "EvalDecision": "allowed",
            "MatchedStatements": [...]
        }
    ]
}
```

### Step 3：驗證 Permission Boundary 已設定

```bash
# 查看 Role 的 PermissionsBoundary 欄位
aws iam get-role --role-name iam-lab-developer-role \
  --query "Role.PermissionsBoundary"
# 預期：{ "PermissionsBoundaryType": "Policy", "PermissionsBoundaryArn": "arn:aws:iam::..." }
```

### 結束

```bash
terraform destroy -auto-approve
```

## 成本

| 資源 | 費用 |
|------|------|
| IAM Roles / Policies | 完全免費 |
| S3 bucket（空的）× 2 | < $0.001/月 |
| **整個 Lab 合計** | **幾乎免費** |

## Permission Boundary 實際案例

**情境**：你是公司 AWS 管理員，要給開發者可以自己建 IAM Role 的權限，但不能超過他自己的權限。

**沒有 Boundary 的問題**：Developer 建一個 Admin Role → 自己 assume 那個 Role → 變相取得 Admin 權限（特權昇級）

**有 Boundary 的解決方案**：要求 Developer 建的所有 Role 都必須附加指定 Boundary，讓新 Role 的權限不超過 Developer 自己的權限範圍。

## ABAC vs RBAC

| 方式 | 定義 | 優點 | 缺點 |
|------|------|------|------|
| RBAC（Role-Based）| 角色決定權限，如 `arn:aws:s3:::prod-bucket` | 明確、易審計 | 資源增加時要更新 policy |
| ABAC（Attribute-Based）| Tag 決定權限，如 `Team = dev` | 資源增加不需改 policy | 需要嚴格管理 tag |

生產環境通常混用：RBAC 做粗顆粒度控制，ABAC 做細顆粒度。

## 整個學習路線回顧

恭喜完成全部 20 個 Lab！你已學會：

| 階段 | Labs | 技術 |
|------|------|------|
| 基礎設施 | 01-03 | EC2, VPC, S3 |
| 資料層 | 04-05 | RDS, DynamoDB |
| Serverless | 06-09 | Lambda, API Gateway, S3 Trigger |
| 容器化 | 10-14 | ECR, ECS Fargate, App Runner, RDS 整合 |
| Kubernetes | 15-18 | EKS Cluster, Workloads, IRSA, Helm |
| DevOps & 安全 | 19-20 | CloudWatch, IAM Advanced |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `simulate` 回傳 `implicitDeny` 而非 `allowed` | policy 的 Action 或 Condition 設定有誤 |
| `simulate` 回傳 `explicitDeny`（預期 allowed）| Explicit Deny policy 的 Action 範圍太廣（誤包含 ec2:Describe*）|
| `terraform apply` 失敗：`NoSuchEntity`（policy attachment）| Role（TODO 5）建立失敗，先修正 Role 再重跑 |
| Permission Boundary 設定後 `aws iam get-role` 看不到 | Boundary ARN 沒填正確，確認 `aws_iam_policy.permission_boundary.arn` 是否存在 |
| ABAC S3 條件在 simulate 中不生效 | `aws:ResourceTag` 在 IAM simulator 中需要加 `--context-entries` 指定 tag 值才能模擬 |
