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

## 注意事項

- 使用 `us.` 開頭的 Bedrock model ID 時，通常代表使用 cross-region inference profile。
- IAM policy 需要同時考慮 foundation model ARN 與 inference profile ARN。
- `mistral.mistral-large-2402-v1:0` 是直接 foundation model ID，因此只需要 foundation model ARN。
- 錯誤訊息中的 `resource` ARN 是最直接的修正依據。
- 不建議直接使用 `Resource = "*"`，除非只是短暫除錯。
