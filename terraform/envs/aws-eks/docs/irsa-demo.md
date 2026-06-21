# IRSA (IAM Roles for Service Accounts) 實戰紀錄

## 概念

IRSA 讓 Kubernetes Pod 直接取得 AWS IAM Role 的權限，不需要任何 hardcoded credentials。

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
| App 版本 | custom-app v3 (Go 1.24 + aws-sdk-go-v2) |

---

## 架構

```
Internet
  └── ALB (internet-facing)
        └── custom-app Service (v3)
              ├── GET /      → App info (hostname, version, uptime)
              ├── GET /health → "ok"
              └── GET /aws   → S3 ListBuckets ← 透過 IRSA，無任何 credentials
                                                          ↑
                                             ServiceAccount: custom-app
                                             annotation: eks.amazonaws.com/role-arn
                                                          ↑
                                             IAM Role trust policy (OIDC Condition)
```

---

## 步驟

### 1. 確認 OIDC Provider（已存在於 alb_controller.tf）

OIDC Provider 在建立 AWS LBC 時就已建立。IRSA 的基礎設施已就緒：

```bash
aws iam list-open-id-connect-providers
# arn:aws:iam::661515655645:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/6408A298B408FB46D9BEF1BCB403D746
```

### 2. 建立 IAM Role（irsa.tf）

trust policy 的關鍵是 `StringEquals` 條件，精確鎖定到特定 namespace + ServiceAccount 名稱：

```hcl
resource "aws_iam_role" "custom_app" {
  name = "${local.name_prefix}-custom-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:custom-app:custom-app"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "custom_app_s3" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListAllMyBuckets"]
      Resource = "*"
    }]
  })
}
```

`sub` 格式固定為：`system:serviceaccount:<namespace>:<serviceaccount-name>`

```bash
terraform apply -target=aws_iam_role.custom_app -target=aws_iam_role_policy.custom_app_s3

# 輸出 Role ARN：
# custom_app_role_arn = "arn:aws:iam::661515655645:role/infra-lab-dev-custom-app-role"
```

### 3. 建立 Kubernetes ServiceAccount

```yaml
# k8s/custom-app/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: custom-app
  namespace: custom-app
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::661515655645:role/infra-lab-dev-custom-app-role
```

annotation 是 IRSA 的接合點：EKS 讀到這個 annotation，在 Pod 啟動時自動注入 OIDC token。

### 4. 更新 Deployment 使用 ServiceAccount

```yaml
# k8s/custom-app/deployment.yaml
spec:
  serviceAccountName: custom-app   # ← 新增這行
  containers:
    - name: app
      image: ...infra-lab-dev-app:v3  # ← 升級到 v3
```

### 5. 新增 /aws endpoint（main.go v3）

AWS SDK v2 的 `config.LoadDefaultConfig` 自動走 credential chain，在 EKS 上會找到 IRSA token：

```go
mux.HandleFunc("/aws", func(w http.ResponseWriter, r *http.Request) {
    cfg, err := config.LoadDefaultConfig(r.Context())
    // SDK 自動從 /var/run/secrets/eks.amazonaws.com/serviceaccount/token 取得 credentials
    client := s3.NewFromConfig(cfg)
    result, err := client.ListBuckets(r.Context(), &s3.ListBucketsInput{})
    // ...回傳 bucket 清單
})
```

### 6. 更新 Dockerfile（Go 1.24）

最新 aws-sdk-go-v2 要求 Go >= 1.24：

```dockerfile
FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go mod init demo && \
    go get github.com/aws/aws-sdk-go-v2/config && \
    go get github.com/aws/aws-sdk-go-v2/service/s3 && \
    go build -o server .

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
```

> ⚠️ 注意：ca-certificates 是呼叫 AWS HTTPS API 所必須的，alpine 預設不含。

### 7. Build 並推到 ECR

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app

docker build -t infra-lab-dev-app:v3 .
docker tag infra-lab-dev-app:v3 661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v3
docker push 661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v3
```

### 8. Push 到 Git，ArgoCD 自動同步

```bash
git add terraform/envs/aws-eks/
git commit -m "feat(aws-eks): 新增 IRSA Demo"
git push
```

ArgoCD 偵測到 HEAD 變更後自動 sync，rolling update v2 → v3。

---

## 觀察結果

### Pod 狀態

```
NAME                          READY   STATUS    IMAGE
custom-app-669bb84774-hvvsm   1/1     Running   infra-lab-dev-app:v3
custom-app-669bb84774-ppczn   1/1     Running   infra-lab-dev-app:v3
```

### 驗證 IRSA 是否成功

```bash
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

Pod 在沒有任何環境變數 credentials 的情況下，成功列出帳號下所有 S3 bucket。

---

## IRSA 的安全優勢

| 對比 | 傳統方式（Access Key） | IRSA |
|------|----------------------|------|
| 憑證存放 | Secret / 環境變數 | 無（動態 STS token） |
| 最小權限範圍 | Node 等級 | Pod / ServiceAccount 等級 |
| 憑證輪換 | 手動 | 自動（token 有效期 1hr） |
| 洩漏風險 | 高（Key 可複製使用） | 低（token 綁定 OIDC sub） |
| CloudTrail 審計 | 只看到 Key ID | 看到 SA identity + Pod |

---

## 遇到的問題

### aws-sdk-go-v2 需要 Go 1.24+

**錯誤訊息：**
```
go: github.com/aws/aws-sdk-go-v2/config@v1.32.25 requires go >= 1.24
(running go 1.22.12; GOTOOLCHAIN=local)
```

**解法：** Dockerfile 的 base image 從 `golang:1.22-alpine` 升為 `golang:1.24-alpine`。

---

## 進階驗證

```bash
# 查看 EKS 注入的 IRSA token 位置
kubectl describe pod <pod-name> -n custom-app | grep -A10 "Volumes"
# 會看到 aws-iam-token volume 掛在 /var/run/secrets/eks.amazonaws.com/serviceaccount/token

# 查看 IAM Role 的 trust policy
aws iam get-role --role-name infra-lab-dev-custom-app-role \
  --query 'Role.AssumeRolePolicyDocument' --output json

# 確認 ServiceAccount annotation
kubectl get sa custom-app -n custom-app -o yaml
```

---

## 常用指令

```bash
# 查看 ServiceAccount
kubectl describe sa custom-app -n custom-app

# 即時看 Pod 更新狀態
kubectl rollout status deployment/custom-app -n custom-app

# 直接在 Pod 裡測試 AWS 呼叫
kubectl exec -n custom-app deploy/custom-app -- \
  wget -qO- http://localhost:8080/aws
```

---

*紀錄日期：2026-06-21*
*環境：AWS EKS 1.36 / aws-sdk-go-v2 v1.42.0 / Go 1.24*
