# IRSA (IAM Roles for Service Accounts) 實戰紀錄

## 概念

IRSA 讓 Kubernetes Pod 直接取得 AWS IAM Role 的權限，不需要：
- ❌ 硬編碼 Access Key / Secret Key
- ❌ 在 Pod 裡放 `~/.aws/credentials`
- ❌ 給 EC2 Node 過大的 IAM 權限

信任鏈：
```
Pod Token
  → Kubernetes ServiceAccount
  → EKS OIDC Provider
  → AWS STS (AssumeRoleWithWebIdentity)
  → IAM Role
  → AWS API (S3, DynamoDB, etc.)
```

---

## 環境

| 項目 | 值 |
|------|-----|
| Cluster | `infra-lab-dev-eks` (EKS 1.36) |
| OIDC Provider | `oidc.eks.us-east-1.amazonaws.com/id/6408A298B408FB46D9BEF1BCB403D746` |
| IAM Role | `arn:aws:iam::661515655645:role/infra-lab-dev-custom-app-role` |
| 權限 | `s3:ListAllMyBuckets` |
| Demo Endpoint | `GET /aws` |

---

## 架構

```
Internet
  └── ALB
        └── custom-app Pod (v3)
              ├── GET /      → App info (JSON)
              ├── GET /health → "ok"
              └── GET /aws   → S3 ListBuckets (via IRSA)
                                    ↓
                            ServiceAccount: custom-app
                                    ↓ OIDC Token
                            IAM Role: custom-app-role
                                    ↓ sts:AssumeRoleWithWebIdentity
                            s3:ListAllMyBuckets
```

---

## 實作步驟

### 1. 確認 OIDC Provider 存在（已在 alb_controller.tf 建立）

```bash
aws iam list-open-id-connect-providers
```

### 2. 建立 IAM Role（irsa.tf）

Trust Policy 的核心是 `StringEquals` 條件，綁定到特定的 ServiceAccount：

```hcl
resource "aws_iam_role" "custom_app" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:custom-app:custom-app"
        }
      }
    }]
  })
}
```

`sub` 格式：`system:serviceaccount:<namespace>:<serviceaccount-name>`

### 3. 建立 Kubernetes ServiceAccount（serviceaccount.yaml）

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: custom-app
  namespace: custom-app
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::661515655645:role/infra-lab-dev-custom-app-role
```

annotation 告訴 EKS：這個 SA 的 Pod 可以取用此 IAM Role。

### 4. Deployment 使用 ServiceAccount

```yaml
spec:
  serviceAccountName: custom-app
```

### 5. App 使用 AWS SDK（不需要傳入 credentials）

```go
cfg, err := config.LoadDefaultConfig(ctx)
// SDK 自動從 Pod 的 IRSA token 取得 credentials
client := s3.NewFromConfig(cfg)
result, err := client.ListBuckets(ctx, &s3.ListBucketsInput{})
```

SDK 的 credential chain 會自動找到 `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`（由 EKS 注入）。

---

## 驗證

```bash
# 呼叫 /aws endpoint
ALB=$(kubectl get ingress custom-app -n custom-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl http://$ALB/aws
```

實際回應（2026-06-21）：

```json
{
    "note": "called via IRSA — no hardcoded credentials",
    "region": "us-east-1",
    "buckets": [
        "aws-athena-changken-us-east-1",
        "cf-templates-1nromuz5m8e8f-us-east-1",
        "elasticbeanstalk-us-east-1-661515655645",
        "elasticbeanstalk-us-west-2-661515655645",
        "sagemaker-studio-661515655645-1v1r742wmfz",
        "sagemaker-studio-661515655645-2z49sf7dx91",
        "sagemaker-us-east-1-661515655645"
    ],
    "count": 7
}
```

---

## IRSA 的安全優勢

| 對比 | 傳統方式 | IRSA |
|------|---------|------|
| 憑證存放 | Secret / 環境變數 | 無（動態 STS token） |
| 最小權限 | Node 等級 | Pod / SA 等級 |
| 憑證輪換 | 手動 | 自動（token 有效期 1hr） |
| 洩漏風險 | 高（Key 可複製） | 低（token 綁定 OIDC） |
| 審計 | Access Key 難追蹤 | CloudTrail 可見 SA identity |

---

## 驗證 IRSA Token（可選）

```bash
# 查看 EKS 注入的 IRSA token
kubectl exec -n custom-app deploy/custom-app -- \
  cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token

# decode JWT，iss/sub 對應到 OIDC/ServiceAccount
```

---

## 常用指令

```bash
# 查看 ServiceAccount 的 annotation
kubectl describe sa custom-app -n custom-app

# 查看 Pod 是否掛入 IRSA token
kubectl describe pod <pod-name> -n custom-app | grep -A5 "Volumes"

# 查看 IAM Role trust policy
aws iam get-role --role-name infra-lab-dev-custom-app-role \
  --query 'Role.AssumeRolePolicyDocument' --output json

# 直接用 kubectl exec 測試 AWS CLI（若 Pod 有裝）
kubectl exec -n custom-app deploy/custom-app -- \
  aws s3 ls --region us-east-1
```

---

*紀錄日期：2026-06-21*
*環境：AWS EKS 1.36 / aws-sdk-go-v2 / IRSA*
