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
  → AWS API (S3, Bedrock, etc.)
```

---

## 環境

| 項目 | 值 |
|------|-----|
| Cluster | `infra-lab-dev-eks` (EKS 1.36) |
| OIDC Provider | `oidc.eks.us-east-1.amazonaws.com/id/6408A298B408FB46D9BEF1BCB403D746` |
| IAM Role | `arn:aws:iam::661515655645:role/infra-lab-dev-custom-app-role` |
| 權限 | `s3:ListAllMyBuckets`、`bedrock:Converse`、`bedrock:InvokeModel` |
| App 版本 | custom-app v6 (Go 1.24 + aws-sdk-go-v2 + prometheus/client_golang) |

---

## 架構

```
Internet
  └── ALB (internet-facing)
        └── custom-app Service (v6)
              ├── GET /        → App info (hostname, version, uptime)
              ├── GET /health  → "ok"
              ├── GET /version → version + go_version
              ├── GET /aws     → S3 ListBuckets     ┐
              ├── GET /chat    → Bedrock Converse    ┤ 透過 IRSA，無任何 credentials
              ├── GET /models  → 支援的 model 清單   ┘
              └── GET /metrics → Prometheus exposition format
                                          ↑
                               ServiceAccount: custom-app
                               annotation: eks.amazonaws.com/role-arn
                                          ↑
                               IAM Role trust policy (OIDC Condition)
                               Policy 1: s3:ListAllMyBuckets
                               Policy 2: bedrock:Converse + InvokeModel (4 models)
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
```

`sub` 格式固定為：`system:serviceaccount:<namespace>:<serviceaccount-name>`

#### Policy 1 — S3

```hcl
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

#### Policy 2 — Bedrock

```hcl
resource "aws_iam_role_policy" "custom_app_bedrock" {
  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock:InvokeModel", "bedrock:Converse"]
      # us.* inference profiles route across us-east-1/us-east-2/us-west-2
      # region wildcard is required; model/profile IDs are explicitly locked
      Resource = [
        "arn:aws:bedrock:*::foundation-model/amazon.nova-lite-v1:0",
        "arn:aws:bedrock:*::foundation-model/meta.llama3-1-8b-instruct-v1:0",
        "arn:aws:bedrock:*::foundation-model/deepseek.r1-v1:0",
        "arn:aws:bedrock:*::foundation-model/meta.llama4-scout-17b-instruct-v1:0",
        "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.amazon.nova-lite-v1:0",
        "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.meta.llama3-1-8b-instruct-v1:0",
        "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.deepseek.r1-v1:0",
        "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.meta.llama4-scout-17b-instruct-v1:0",
      ]
    }]
  })
}
```

```bash
terraform apply -target=aws_iam_role.custom_app \
  -target=aws_iam_role_policy.custom_app_s3 \
  -target=aws_iam_role_policy.custom_app_bedrock

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
  serviceAccountName: custom-app
  containers:
    - name: app
      image: ...infra-lab-dev-app:v6
      imagePullPolicy: Always   # mutable tag 必加，確保每次都拉最新
```

### 5. 新增 /aws endpoint（S3 via IRSA）

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

### 6. 新增 /chat endpoint（Bedrock Converse via IRSA）

Bedrock Converse API 是 model-agnostic 介面，同一支程式碼可以呼叫任何 Bedrock 支援的模型：

```go
// model 別名 → Bedrock cross-region inference profile ID
var modelAliases = map[string]string{
    "nova":     "us.amazon.nova-lite-v1:0",
    "llama":    "us.meta.llama3-1-8b-instruct-v1:0",
    "deepseek": "us.deepseek.r1-v1:0",
    "llama4":   "us.meta.llama4-scout-17b-instruct-v1:0",
}

mux.HandleFunc("/chat", func(w http.ResponseWriter, r *http.Request) {
    // 1. API Key 驗證（X-API-Key header）
    if chatAPIKey != "" && r.Header.Get("X-API-Key") != chatAPIKey {
        http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
        return
    }

    // 2. 解析 ?model= 參數，嚴格 allowlist，不在清單內直接 400
    modelID, ok := modelAliases[r.URL.Query().Get("model")]
    if !ok {
        http.Error(w, `{"error":"unknown model"}`, http.StatusBadRequest)
        return
    }

    // 3. 用 IRSA credentials 呼叫 Bedrock（零 hardcode）
    cfg, _ := config.LoadDefaultConfig(r.Context())
    client := brt.NewFromConfig(cfg)
    resp, _ := client.Converse(r.Context(), &brt.ConverseInput{
        ModelId: aws.String(modelID),
        Messages: []brtypes.Message{{
            Role:    brtypes.ConversationRoleUser,
            Content: []brtypes.ContentBlock{&brtypes.ContentBlockMemberText{Value: query}},
        }},
    })
    // ...回傳 reply
})
```

**為什麼用 cross-region inference profile（`us.*` 前綴）？**

Bedrock on-demand throughput 部分模型（如 DeepSeek R1、Llama 4）不支援直接呼叫 foundation-model ARN，
必須用 cross-region inference profile，讓 Bedrock 自動在 us-east-1 / us-east-2 / us-west-2 之間路由。

| 呼叫方式 | ARN 格式 | 適用場景 |
|---------|---------|---------|
| Foundation Model 直呼 | `arn:aws:bedrock:us-east-1::foundation-model/...` | 有 Provisioned Throughput |
| Cross-Region Profile | `us.amazon.nova-lite-v1:0`（簡短 ID） | On-demand，自動跨 region 路由 |

### 7. 安全強化：API Key 認證

`/chat` 對外開放但不加保護等於免費 LLM proxy。用 K8s Secret 儲存 API Key：

```bash
# 產生隨機 key
API_KEY=$(openssl rand -hex 20)
kubectl create secret generic custom-app-secrets \
  --from-literal=chat-api-key=$API_KEY \
  -n custom-app
```

Deployment 透過 `secretKeyRef` 注入（不寫死在 YAML）：

```yaml
env:
  - name: CHAT_API_KEY
    valueFrom:
      secretKeyRef:
        name: custom-app-secrets
        key: chat-api-key
        optional: true   # 不設 secret 時 endpoint 公開（開發用）
```

### 8. Build 並推到 ECR

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  661515655645.dkr.ecr.us-east-1.amazonaws.com

docker build -t infra-lab-dev-app:v6 .
docker tag infra-lab-dev-app:v6 \
  661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v6
docker push 661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v6
```

### 9. Push 到 Git，ArgoCD 自動同步

```bash
git add terraform/envs/aws-eks/
git commit -m "feat(aws-eks): 新增 IRSA + Bedrock Demo"
git push
```

ArgoCD 偵測到 HEAD 變更後自動 sync，rolling update 舊版 → v6。

---

## 觀察結果

### Pod 狀態

```
NAME                          READY   STATUS    IMAGE
custom-app-xxx-aaa            1/1     Running   infra-lab-dev-app:v6
custom-app-xxx-bbb            1/1     Running   infra-lab-dev-app:v6
```

### 驗證 S3 via IRSA

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

### 驗證 Bedrock Converse via IRSA

```bash
ALB=$(kubectl get ingress custom-app -n custom-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

API_KEY=$(kubectl get secret custom-app-secrets -n custom-app \
  -o jsonpath='{.data.chat-api-key}' | base64 -d)

# 查看支援的 model
curl http://$ALB/models

# 呼叫各 model
curl "http://$ALB/chat?q=say+hello+in+one+sentence&model=nova" \
  -H "X-API-Key: $API_KEY"

curl "http://$ALB/chat?q=say+hello+in+one+sentence&model=llama" \
  -H "X-API-Key: $API_KEY"

curl "http://$ALB/chat?q=say+hello+in+one+sentence&model=deepseek" \
  -H "X-API-Key: $API_KEY"

curl "http://$ALB/chat?q=say+hello+in+one+sentence&model=llama4" \
  -H "X-API-Key: $API_KEY"
```

實際回應（2026-06-22）：

| Model | ID | 回應 |
|-------|----|------|
| nova | `us.amazon.nova-lite-v1:0` | `Hello there, how are you doing today?` |
| llama | `us.meta.llama3-1-8b-instruct-v1:0` | `Hello!` |
| deepseek | `us.deepseek.r1-v1:0` | `Hello! How can I assist you today?` |
| llama4 | `us.meta.llama4-scout-17b-instruct-v1:0` | `Hello!` |

Pod 在沒有任何 hardcoded credentials 的情況下，透過 IRSA 成功呼叫 Bedrock Converse API。

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

## 安全審查修正記錄

### 問題 1 — allowlist bypass

**原始程式碼（有漏洞）：**
```go
modelID, ok := modelAliases[modelAlias]
if !ok {
    modelID = modelAlias  // ← 讓 user 直接傳任意 model ID！
}
```

**修正：** 未知 alias 直接回傳 400，不允許繞過 allowlist。

### 問題 2 — 未驗證的 LLM Proxy

`/chat` endpoint 未加任何驗證 → 任何人都能用你的 AWS 帳號免費呼叫 Bedrock。

**修正：** 加 `X-API-Key` header 驗證，key 存在 K8s Secret，透過 `secretKeyRef` 注入。

### 問題 3 — IAM 過度授權

**原始 policy（過寬）：**
```hcl
Resource = ["arn:aws:bedrock:*::foundation-model/*"]  # 允許呼叫所有模型
```

**修正：** 明確列出 4 個 foundation-model ARN + 4 個 inference-profile ARN，拒絕其他一切。

---

## 遇到的問題

### aws-sdk-go-v2 需要 Go 1.24+

**錯誤訊息：**
```
go: github.com/aws/aws-sdk-go-v2/config@v1.32.25 requires go >= 1.24
```

**解法：** Dockerfile base image 從 `golang:1.22-alpine` 升為 `golang:1.24-alpine`。

### DeepSeek / Llama 4 on-demand 不支援

**錯誤訊息：**
```
ValidationException: Invocation of model ID deepseek.r1-v1:0 with on-demand throughput isn't supported
```

**原因：** 部分模型不支援直接呼叫 foundation-model ARN，需走 cross-region inference profile。

**解法：** 所有 model 改用 `us.*` 前綴的 inference profile ID。

### IAM Policy 需要同時授權 foundation-model 和 inference-profile ARN

cross-region inference profile 實際上會再呼叫 foundation-model，因此 IAM 必須兩者都允許：
- `arn:aws:bedrock:*::foundation-model/<model-id>` — region wildcard 覆蓋 3 個 US region
- `arn:aws:bedrock:<region>:<account>:inference-profile/us.<model-id>` — profile 本身的 ARN

### stale image cache（imagePullPolicy 問題）

**症狀：** `rollout restart` 後 Pod 用的還是舊 image。

**原因：** tag `v4` 已 cache 在 Node 上，`IfNotPresent` policy 不重拉。

**解法：** deployment.yaml 加 `imagePullPolicy: Always`。

---

## 進階驗證

```bash
# 查看 EKS 注入的 IRSA token 位置
kubectl describe pod <pod-name> -n custom-app | grep -A10 "Volumes"
# 會看到 aws-iam-token volume 掛在 /var/run/secrets/eks.amazonaws.com/serviceaccount/token

# 查看 IAM Role 的 trust policy
aws iam get-role --role-name infra-lab-dev-custom-app-role \
  --query 'Role.AssumeRolePolicyDocument' --output json

# 查看目前 Bedrock 授權的 policy
aws iam get-role-policy \
  --role-name infra-lab-dev-custom-app-role \
  --policy-name infra-lab-dev-custom-app-bedrock

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

# 直接在 Pod 裡測試 S3
kubectl exec -n custom-app deploy/custom-app -- \
  wget -qO- http://localhost:8080/aws

# 直接在 Pod 裡測試 Bedrock
kubectl exec -n custom-app deploy/custom-app -- \
  wget -qO- "http://localhost:8080/chat?q=hello&model=nova"
# ↑ 在 Pod 內部繞過 API Key（CHAT_API_KEY 驗證走 header，wget 不帶）
# 若要帶 key：
kubectl exec -n custom-app deploy/custom-app -- \
  wget -qO- --header="X-API-Key: <key>" \
  "http://localhost:8080/chat?q=hello&model=nova"

# 查看 Prometheus 指標
curl http://$ALB/metrics | grep custom_app
```

---

## 延伸閱讀

| 文件 | 說明 |
|------|------|
| [rag-demo.md](./rag-demo.md) | 以 IRSA 為基礎，同時串接 S3 + Bedrock 實作 Poor Man's RAG |
| [monitoring-demo.md](./monitoring-demo.md) | kube-prometheus-stack 可觀測性，觀察 IRSA 呼叫次數指標 |

**IRSA 應用演進路徑：**

```
Step 1: IRSA 基礎（本文）
  └── IAM Role + ServiceAccount + OIDC
        └── /aws → s3:ListAllMyBuckets

Step 2: IRSA × Bedrock（本文）
  └── bedrock:Converse policy
        └── /chat → 4 個 open LLM model

Step 3: IRSA × S3 × Bedrock（rag-demo.md）
  └── s3:GetObject policy
        └── /rag → S3 knowledge base → Bedrock system prompt → RAG
```

---

*紀錄日期：2026-06-22*
*環境：AWS EKS 1.36 / aws-sdk-go-v2 v1.42.0 / Go 1.24 / Bedrock Converse API*
