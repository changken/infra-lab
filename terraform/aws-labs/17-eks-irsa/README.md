# Lab 17: EKS IRSA（IAM Roles for Service Accounts）

讓 Kubernetes Pod 透過 Service Account 自動取得 AWS IAM 臨時憑證，不需要 hardcode 任何密鑰。
**費用等級 🔴 危險** — 需搭配 Lab 15 的 EKS Cluster，Lab 17 本身不額外增加費用。

**前置條件**：Lab 15 的 EKS Cluster 必須是 `ACTIVE` 狀態，且 `kubectl get nodes` 顯示節點 `Ready`。

## 學習目標

- **IRSA 機制**：OIDC Provider → IAM Role → Service Account → Pod 的完整信任鏈
- `aws_iam_openid_connect_provider`：讓 AWS 信任 EKS OIDC 端點（IRSA 基礎設施層）
- IAM Role 的 OIDC Trust Policy：`sts:AssumeRoleWithWebIdentity`、`Federated` Principal、`StringEquals` Condition
- `kubernetes_service_account`：`eks.amazonaws.com/role-arn` annotation 是 IRSA 的觸發器
- Pod spec 的 `service_account_name`：讓 EKS 自動掛載 IAM 臨時憑證到容器

## 架構

```
┌─────────────────────────────────────────────────────────┐
│  AWS IAM                                                 │
│                                                          │
│  OIDC Provider（信任 EKS OIDC 端點）                    │
│       ↕ trust                                            │
│  IAM Role（eks-irsa-role）                              │
│       Condition: sub = system:serviceaccount:irsa-demo:eks-irsa-sa
│       Policy: AmazonS3ReadOnlyAccess                    │
└──────────────────┬──────────────────────────────────────┘
                   │ annotation: eks.amazonaws.com/role-arn
┌──────────────────▼──────────────────────────────────────┐
│  Kubernetes（EKS Cluster）                              │
│                                                          │
│  Namespace: irsa-demo                                   │
│  ServiceAccount: eks-irsa-sa  ← annotation 指向 IAM Role│
│  Pod（amazon/aws-cli）                                  │
│       serviceAccountName: eks-irsa-sa                   │
│       ← EKS 自動注入 AWS_ROLE_ARN 等環境變數            │
└─────────────────────────────────────────────────────────┘
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_iam_role.app` | Trust Policy：`AssumeRoleWithWebIdentity`，`Federated` Principal，`StringEquals` Condition |
| 2 | `aws_iam_role_policy_attachment.app` | `AmazonS3ReadOnlyAccess`（用來驗證 IRSA 功能）|
| 3 | `kubernetes_namespace.app` | 已學過 |
| 4 | `kubernetes_service_account.app` | `eks.amazonaws.com/role-arn` annotation（IRSA 觸發器）|
| 5 | `kubernetes_deployment.app` | `service_account_name` 讓 EKS 掛載 IAM 憑證到 Pod |

已預填：EKS data sources、TLS 憑證 data source、OIDC Provider、Kubernetes provider 設定

## IRSA Trust Policy 詳解

這是整個 Lab 最重要的部分，與前面學過的 IAM Role 有三個關鍵差異：

```hcl
assume_role_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect = "Allow"

    # 差異 1：Principal 是 Federated（OIDC Provider ARN），不是 Service！
    Principal = {
      Federated = aws_iam_openid_connect_provider.eks.arn
    }

    # 差異 2：Action 是 AssumeRoleWithWebIdentity，不是 AssumeRole！
    Action = "sts:AssumeRoleWithWebIdentity"

    # 差異 3：Condition 限制只有特定 Service Account 才能 assume 這個 Role
    Condition = {
      StringEquals = {
        "${local.oidc_issuer}:sub" = "system:serviceaccount:<namespace>:<sa-name>"
        "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
      }
    }
  }]
})
```

**為什麼需要 Condition？**  
沒有 Condition，EKS cluster 中所有 Pod 都可以 assume 這個 Role。Condition 把權限鎖定到特定的 namespace + service account。

## 指令

### 前置確認（Lab 15 必須已 apply）

```bash
aws eks describe-cluster --name eks-lab --query "cluster.status"
# 預期：ACTIVE

kubectl get nodes
# 預期：2 個節點 Ready
```

### Step 1：填寫 TODOs 並部署

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：6 to add
terraform apply
```

### Step 2：驗證 IRSA

```bash
# 等待 Pod Running（約 1-2 分鐘）
kubectl get pods -n irsa-demo

# 驗證 Pod 使用的 IAM Role（看 Arn 欄位，應包含 eks-irsa-role）
terraform output verify_command
# 執行輸出的指令，例如：
kubectl exec -n irsa-demo deployment/eks-irsa-app -- aws sts get-caller-identity
```

**預期輸出**（UserId 和 Account 會不同，但 Arn 應包含 `eks-irsa-role`）：
```json
{
    "UserId": "AROA...:botocore-session-...",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/eks-irsa-role/botocore-session-..."
}
```

```bash
# 驗證 S3 存取（應能列出你帳號中的 S3 bucket）
kubectl exec -n irsa-demo deployment/eks-irsa-app -- aws s3 ls --region us-east-1

# 驗證環境變數（EKS 自動注入的 IRSA 環境變數）
kubectl exec -n irsa-demo deployment/eks-irsa-app -- env | grep AWS
# 預期看到：AWS_ROLE_ARN、AWS_WEB_IDENTITY_TOKEN_FILE
```

### 結束

```bash
terraform destroy -auto-approve

# 再回到 Lab 15 destroy EKS cluster
cd ../15-eks-cluster
terraform destroy -auto-approve
```

## 成本

| 資源 | 費用 |
|------|------|
| EKS Control Plane（Lab 15）| $0.10/hr |
| t3.medium × 2 工作節點（Lab 15）| $0.094/hr |
| OIDC Provider / IAM Role | 免費 |
| **3 小時 Lab 合計** | **~$0.58** |

## 沒有 IRSA vs 有 IRSA

| 面向 | 沒有 IRSA | 有 IRSA |
|------|-----------|---------|
| 憑證來源 | 手動建立 Access Key，以 Secret 或環境變數傳入 | EKS 自動注入臨時憑證 |
| 憑證有效期 | 長期（易洩漏）| 短期（15 分鐘，自動輪替）|
| 權限範圍 | 難以限制（通常 cluster 共用一個 Instance Profile）| 每個 Service Account 獨立 IAM Role |
| 最小權限 | 難以實踐 | 可精確控制到 Pod 層級 |

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `aws sts get-caller-identity` 回傳 EC2 role 而非 IRSA role | Service Account annotation 寫錯，或 Deployment 忘記設 `service_account_name` |
| `An error occurred (AccessDenied)` | IAM Role Trust Policy 的 Condition `:sub` 路徑寫錯（namespace 或 sa 名稱不符）|
| `aws: command not found` | Pod 還在 ContainerCreating，或 image `amazon/aws-cli` 拉取失敗（等幾分鐘）|
| `terraform plan` 失敗：`cluster not found` | Lab 15 的 cluster 不存在或 `cluster_name` 與 Lab 15 的 `project` 不符 |
| `identity is empty list of object` 或 `OIDC issuer 尚未可用` | Lab 15 的 EKS cluster 尚未完全 `ACTIVE`，或 AWS 尚未回傳 `identity.oidc.issuer`；先用 `aws eks describe-cluster --name eks-lab --query "cluster.{status:status,issuer:identity.oidc.issuer}"` 確認 |
| OIDC Provider 已存在 error | 一個 EKS cluster 只能有一個 OIDC Provider，先 destroy 再 apply |
