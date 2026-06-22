# Bedrock IRSA 403 修正紀錄

本文記錄 `custom-app` 透過 EKS IRSA 呼叫 Bedrock Converse API 時遇到 `AccessDeniedException` 的排查與修正過程。

## 問題現象

呼叫 `custom-app` 的 `/chat` endpoint：

```bash
curl -H "X-API-Key: $API_KEY" "http://$ALB/chat?q=Hello&model=nova"
```

回傳錯誤：

```text
bedrock error: operation error Bedrock Runtime: Converse, https response error StatusCode: 403,
AccessDeniedException: User: arn:aws:sts::661515655645:assumed-role/infra-lab-dev-custom-app-role/...
is not authorized to perform: bedrock:InvokeModel on resource:
arn:aws:bedrock:us-east-1:661515655645:inference-profile/us.amazon.nova-lite-v1:0
because no identity-based policy allows the bedrock:InvokeModel action
```

## 環境狀態

當時 `terraform/envs/aws-eks` 已部署完成：

- EKS cluster：`infra-lab-dev-eks`
- Region：`us-east-1`
- Node group：`ACTIVE`
- `custom-app` Pod 使用 ServiceAccount：`custom-app`
- ServiceAccount 透過 IRSA 綁定 IAM Role：`infra-lab-dev-custom-app-role`

Terraform 檢查結果：

```bash
terraform -chdir=terraform/envs/aws-eks plan -detailed-exitcode
```

結果顯示 infrastructure 與 Terraform 設定一致，沒有 drift。

## Root Cause

`custom-app` 的 Go 程式中，`model=nova` 會被轉成 Bedrock cross-region inference profile ID：

```go
"nova": "us.amazon.nova-lite-v1:0"
```

呼叫 Bedrock Converse API 時：

```go
client.Converse(ctx, &brt.ConverseInput{
    ModelId: aws.String(modelID),
})
```

當 `ModelId` 是 `us.amazon.nova-lite-v1:0` 時，Bedrock 實際授權檢查的 resource 是：

```text
arn:aws:bedrock:us-east-1:661515655645:inference-profile/us.amazon.nova-lite-v1:0
```

但原本的 `aws_iam_role_policy.custom_app_bedrock` 只允許 foundation model ARN：

```hcl
Resource = [
  "arn:aws:bedrock:*::foundation-model/amazon.nova-lite-v1:0",
  "arn:aws:bedrock:*::foundation-model/meta.llama3-1-8b-instruct-v1:0",
  "arn:aws:bedrock:*::foundation-model/deepseek.r1-v1:0",
  "arn:aws:bedrock:*::foundation-model/meta.llama4-scout-17b-instruct-v1:0",
]
```

因此 IRSA Role 雖然有 Bedrock 權限，但沒有授權到 inference profile ARN，導致 `403 AccessDeniedException`。

## 修正方式

在 `terraform/envs/aws-eks/irsa.tf` 的 `aws_iam_role_policy.custom_app_bedrock` 中，保留原本 foundation model ARN，並補上明確的 inference profile ARN：

```hcl
Resource = [
  "arn:aws:bedrock:*::foundation-model/amazon.nova-lite-v1:0",
  "arn:aws:bedrock:*::foundation-model/meta.llama3-1-8b-instruct-v1:0",
  "arn:aws:bedrock:*::foundation-model/deepseek.r1-v1:0",
  "arn:aws:bedrock:*::foundation-model/meta.llama4-scout-17b-instruct-v1:0",
  "arn:aws:bedrock:*::foundation-model/mistral.mistral-large-2402-v1:0",
  "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.amazon.nova-lite-v1:0",
  "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.meta.llama3-1-8b-instruct-v1:0",
  "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.deepseek.r1-v1:0",
  "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.meta.llama4-scout-17b-instruct-v1:0",
]
```

這樣仍維持最小權限，只允許目前 app 支援的 model/profile，不放寬成所有 Bedrock resources。

## 套用步驟

格式化 Terraform：

```bash
terraform -chdir=terraform/envs/aws-eks fmt
```

產生 plan：

```bash
terraform -chdir=terraform/envs/aws-eks plan -out=tfplan
```

Plan 結果只有一項變更：

```text
Plan: 0 to add, 1 to change, 0 to destroy.
```

變更項目：

```text
aws_iam_role_policy.custom_app_bedrock will be updated in-place
```

套用：

```bash
terraform -chdir=terraform/envs/aws-eks apply tfplan
```

套用結果：

```text
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

## 驗證

取得 ALB：

```bash
ALB=$(kubectl get ingress custom-app -n custom-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

呼叫 chat endpoint：

```bash
curl -H "X-API-Key: $API_KEY" "http://$ALB/chat?q=Hello&model=nova"
```

修正後回傳成功：

```json
{
  "model": "us.amazon.nova-lite-v1:0",
  "query": "Hello",
  "reply": "Hello! How can I assist you today?",
  "via": "IRSA -> bedrock:Converse"
}
```

## Mistral 與 GitOps 部署紀錄

後續檢查發現 `main.go` 的註解與錯誤訊息提到 `mistral`，但 `modelAliases` 尚未實作，因此補上：

```go
"mistral": "mistral.mistral-large-2402-v1:0",
```

同時將 app 版本與 Kubernetes manifest image tag 從 `v4` 更新為 `v5`：

```yaml
image: 661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v5
```

Build 並推送 image：

```bash
docker build -t 661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v5 terraform/envs/aws-eks/app
docker push 661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v5
```

因為 `custom-app` 由 ArgoCD 管理，Application 來源是：

```text
repoURL: https://github.com/changken/infra-lab
path: terraform/envs/aws-eks/k8s/custom-app
targetRevision: HEAD
selfHeal: true
```

直接使用 `kubectl apply` 或 `kubectl set image` 修改 live Deployment 會被 ArgoCD 自動還原成 GitHub 上的版本。因此正確流程是：

```bash
git add terraform/envs/aws-eks/app/main.go \
  terraform/envs/aws-eks/irsa.tf \
  terraform/envs/aws-eks/k8s/custom-app/deployment.yaml \
  terraform/envs/aws-eks/docs/bedrock-irsa-403-fix.md

git commit -m "fix: add bedrock mistral support"
git push origin main
```

本次提交：

```text
30f6b5c fix: add bedrock mistral support
```

Push 後觸發 ArgoCD hard refresh：

```bash
kubectl annotate application custom-app -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

確認 ArgoCD 已同步到新 revision：

```text
30f6b5c3c278c2ef60bbba018d8edf47d0410c63 Synced Healthy
```

確認 live Deployment image：

```text
661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v5
```

確認 `/models` 已包含 `mistral`：

```json
{
  "deepseek": "us.deepseek.r1-v1:0",
  "llama": "us.meta.llama3-1-8b-instruct-v1:0",
  "llama4": "us.meta.llama4-scout-17b-instruct-v1:0",
  "mistral": "mistral.mistral-large-2402-v1:0",
  "nova": "us.amazon.nova-lite-v1:0"
}
```

## 注意事項

- 使用 `us.` 開頭的 Bedrock model ID 時，通常代表使用 cross-region inference profile。
- IAM policy 需要同時考慮 foundation model ARN 與 inference profile ARN。
- `mistral.mistral-large-2402-v1:0` 是直接 foundation model ID，因此只需要 foundation model ARN。
- 錯誤訊息中的 `resource` ARN 是最直接的修正依據。
- ArgoCD 開啟 `selfHeal` 時，live cluster 變更必須回寫 Git，否則會被還原。
- 不建議直接使用 `Resource = "*"`，除非只是短暫除錯。
