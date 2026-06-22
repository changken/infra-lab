# Poor Man's RAG — S3 Knowledge Base + Bedrock

## 概念

RAG（Retrieval-Augmented Generation）的核心思路是：**先撈資料，再問 AI**。
不讓 LLM 憑空回答，而是先把相關資料注入 system prompt，讓模型根據你的資料回答。

```
沒有 RAG：
  user question → LLM → 答案（憑訓練資料）

有 RAG：
  user question → 搜尋/撈資料 → system prompt 注入 → LLM → 答案（根據你的資料）
```

**Poor Man's RAG** 省略了 vector embedding + similarity search，直接把所有知識文件塞進 system prompt。適合：
- 知識庫小（< 幾十 KB）
- 不需要語意搜尋
- 快速驗證 RAG 概念

正式 RAG 的差異：

| 步驟 | 正式 RAG | Poor Man's RAG |
|------|---------|----------------|
| 知識存放 | Vector DB（Pinecone、pgvector） | S3 `.txt` 檔案 |
| 搜尋 | Embedding similarity search | 全部撈下來塞進去 |
| 輸入 LLM | Top-K 相關片段 | 全部內容 |
| 費用 | Vector DB 額外收費 | S3 幾乎免費 |
| 上限 | 取決於 DB | Context window 大小 |

---

## 架構

```
Internet
  └── ALB
        └── GET /rag?q=<question>&model=<alias>
                    │
                    │ 1. s3:ListObjectsV2
                    ├──► S3 Bucket: infra-lab-dev-rag-661515655645
                    │        └── knowledge/
                    │              ├── infra-lab-overview.txt
                    │              ├── irsa-guide.txt
                    │              └── bedrock-models.txt
                    │
                    │ 2. s3:GetObject（每個 .txt，最多 12000 字元）
                    │
                    │ 3. 組裝 system prompt：
                    │    "You are a helpful assistant...
                    │     Context:
                    │     --- <file 1 content> ---
                    │     --- <file 2 content> ---"
                    │
                    │ 4. bedrock:Converse（system + user message）
                    └──► Bedrock Cross-Region Inference Profile
                              └── 回傳 reply + sources + context_chars
```

**所有 AWS 呼叫都走 IRSA** — Pod 沒有任何 hardcoded credentials。

---

## 環境

| 項目 | 值 |
|------|-----|
| S3 Bucket | `infra-lab-dev-rag-661515655645` |
| 知識文件前綴 | `knowledge/` |
| 最大 context | 12,000 字元 |
| IAM Policy | `s3:ListBucket` + `s3:GetObject` on knowledge bucket |
| App 版本 | custom-app v7 |

---

## 步驟

### 1. 建立 S3 Knowledge Base（rag.tf）

```hcl
resource "aws_s3_bucket" "rag_knowledge" {
  bucket = "${local.name_prefix}-rag-${data.aws_caller_identity.current.account_id}"
}

resource "aws_iam_role_policy" "custom_app_s3_rag" {
  role = aws_iam_role.custom_app.id
  policy = jsonencode({
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.rag_knowledge.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.rag_knowledge.arn}/knowledge/*"
      }
    ]
  })
}
```

IAM Policy 只開放 `knowledge/` prefix，bucket 其他路徑不可讀。

```bash
terraform apply \
  -target=aws_s3_bucket.rag_knowledge \
  -target=aws_s3_bucket_public_access_block.rag_knowledge \
  -target=aws_iam_role_policy.custom_app_s3_rag \
  -target=aws_s3_object.infra_lab_overview \
  -target=aws_s3_object.irsa_guide \
  -target=aws_s3_object.bedrock_models
```

### 2. 知識文件（terraform apply 自動上傳）

`rag.tf` 用 `aws_s3_object` 預載 3 份文件：

| 檔案 | 內容 |
|------|------|
| `knowledge/infra-lab-overview.txt` | EKS cluster 架構、費用、運行中的服務 |
| `knowledge/irsa-guide.txt` | IRSA 運作原理、trust policy 說明 |
| `knowledge/bedrock-models.txt` | 支援的 model alias 與 API 使用方式 |

想新增自己的知識：
```bash
# 手動上傳任何 .txt 檔
aws s3 cp my-knowledge.txt \
  s3://infra-lab-dev-rag-661515655645/knowledge/my-knowledge.txt
```

### 3. /rag endpoint 實作（main.go v7）

```go
mux.HandleFunc("/rag", func(w http.ResponseWriter, r *http.Request) {
    // 1. 列出 knowledge/ 下所有 .txt
    listResult, _ := s3Client.ListObjectsV2(ctx, &s3.ListObjectsV2Input{
        Bucket: aws.String(knowledgeBucket),
        Prefix: aws.String("knowledge/"),
    })

    // 2. 逐一 GetObject，累積最多 12000 字元
    var contextParts []string
    for _, obj := range listResult.Contents {
        body, _ := s3Client.GetObject(ctx, &s3.GetObjectInput{...})
        contextParts = append(contextParts, string(body))
    }

    // 3. 組 system prompt
    systemPrompt := "You are a helpful assistant...\n\nContext:\n---\n" +
        strings.Join(contextParts, "\n---\n")

    // 4. Bedrock Converse（帶 System 參數）
    resp, _ := bedrockClient.Converse(ctx, &brt.ConverseInput{
        ModelId: aws.String(modelID),
        System: []brtypes.SystemContentBlock{
            &brtypes.SystemContentBlockMemberText{Value: systemPrompt},
        },
        Messages: []brtypes.Message{{
            Role:    brtypes.ConversationRoleUser,
            Content: []brtypes.ContentBlock{
                &brtypes.ContentBlockMemberText{Value: query},
            },
        }},
    })
    // 回傳 reply + sources + context_chars
})
```

### 4. 設定 Deployment 環境變數

```yaml
# k8s/custom-app/deployment.yaml
env:
  - name: KNOWLEDGE_BUCKET
    value: "infra-lab-dev-rag-661515655645"   # terraform output rag_knowledge_bucket
```

### 5. Build v7 並部署

```bash
docker build -t infra-lab-dev-app:v7 .
docker tag infra-lab-dev-app:v7 \
  661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v7
docker push 661515655645.dkr.ecr.us-east-1.amazonaws.com/infra-lab-dev-app:v7

git add terraform/envs/aws-eks/
git commit -m "feat(aws-eks): 新增 Poor Man's RAG"
git push
# ArgoCD 自動 sync → rolling update v6 → v7
```

---

## 驗證

### 基本測試

```bash
ALB=$(kubectl get ingress custom-app -n custom-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

API_KEY=$(kubectl get secret custom-app-secrets -n custom-app \
  -o jsonpath='{.data.chat-api-key}' | base64 -d)

# 問 EKS cluster 有哪些服務
curl "http://$ALB/rag?q=what+applications+are+running+in+the+cluster&model=nova" \
  -H "X-API-Key: $API_KEY"

# 問 IRSA 怎麼運作
curl "http://$ALB/rag?q=how+does+IRSA+work&model=deepseek" \
  -H "X-API-Key: $API_KEY"

# 問 lab 每天花多少錢
curl "http://$ALB/rag?q=how+much+does+this+lab+cost+per+day&model=llama4" \
  -H "X-API-Key: $API_KEY"
```

### 實際回應（2026-06-22）

**問：what applications are running in the cluster（nova）**
```json
{
    "model": "us.amazon.nova-lite-v1:0",
    "query": "what applications are running in the cluster",
    "reply": "The applications running in the cluster are:\n\n1. **custom-app** (namespace: custom-app) - A Go HTTP service that demonstrates IRSA + Bedrock + RAG.\n2. **podinfo** (namespace: podinfo) - A reference microservice for traffic testing.\n3. **ArgoCD** (namespace: argocd) - The GitOps controller.\n4. **kube-prometheus-stack** (namespace: monitoring) - A stack for Prometheus and Grafana observability.",
    "sources": [
        "knowledge/bedrock-models.txt",
        "knowledge/infra-lab-overview.txt",
        "knowledge/irsa-guide.txt"
    ],
    "context_chars": 4061,
    "via": "IRSA → s3:GetObject → bedrock:Converse"
}
```

**問：how does IRSA work and what are its benefits（deepseek）**

DeepSeek R1 的 chain-of-thought 特性使回答更有結構，逐步列出 trust chain 每個步驟，並對應到 lab 實際的 Role ARN 和 ServiceAccount。（完整回應見測試輸出）

### 確認 S3 文件被正確讀取

```bash
# 查看 knowledge bucket 內容
aws s3 ls s3://infra-lab-dev-rag-661515655645/knowledge/

# 直接讀一個文件
aws s3 cp s3://infra-lab-dev-rag-661515655645/knowledge/irsa-guide.txt -
```

### Prometheus 指標

```bash
curl http://$ALB/metrics | grep rag
# custom_app_rag_context_chars_bucket{...}   ← context 大小分佈（Histogram）
# custom_app_bedrock_requests_total{model="nova",status="ok"}
```

Grafana Explore 查詢：
```promql
# RAG 平均 context 大小
histogram_quantile(0.5, rate(custom_app_rag_context_chars_bucket[5m]))

# RAG vs 一般 chat 的呼叫比例
sum by (path) (rate(custom_app_http_requests_total[5m]))
```

---

## RAG vs 直接問 /chat 的差異

```bash
# 沒有 context，LLM 憑訓練資料回答
curl "http://$ALB/chat?q=what+applications+are+running+in+the+cluster&model=nova" \
  -H "X-API-Key: $API_KEY"
# → 會亂猜，或說「我不知道你的具體環境」

# 有 S3 context，回答基於你自己的文件
curl "http://$ALB/rag?q=what+applications+are+running+in+the+cluster&model=nova" \
  -H "X-API-Key: $API_KEY"
# → 準確列出 custom-app / podinfo / ArgoCD / kube-prometheus-stack
```

---

## 新增自己的知識文件

### 方法 1：手動上傳

```bash
# 任何 .txt 檔，放進 knowledge/ prefix 即可
echo "My custom knowledge content" > my-doc.txt
aws s3 cp my-doc.txt \
  s3://infra-lab-dev-rag-661515655645/knowledge/my-doc.txt

# 立刻生效（下次 /rag 請求自動包含）
```

### 方法 2：Terraform 管理（推薦）

在 `rag.tf` 加一個 `aws_s3_object`：

```hcl
resource "aws_s3_object" "my_knowledge" {
  bucket  = aws_s3_bucket.rag_knowledge.id
  key     = "knowledge/my-knowledge.txt"
  content = <<-EOT
    ... 你的知識內容 ...
  EOT
  etag    = md5("my-knowledge-v1")
}
```

```bash
terraform apply -target=aws_s3_object.my_knowledge
```

---

## 遇到的問題

| 症狀 | 原因 | 解法 |
|------|------|------|
| `KNOWLEDGE_BUCKET not configured` | deployment.yaml 沒設 `KNOWLEDGE_BUCKET` | 補上 env var，值為 `terraform output rag_knowledge_bucket` |
| `s3:ListObjectsV2 failed: AccessDenied` | IAM policy 沒加 s3:ListBucket | 確認 `custom_app_s3_rag` policy 已 apply |
| context_chars = 0，reply 不準確 | `.txt` 副檔名不符 / prefix 路徑錯誤 | `aws s3 ls s3://<bucket>/knowledge/` 確認檔案存在 |
| Pod Pending（Too many pods） | 加了 monitoring stack 後節點資源不足 | Node Group desiredSize 加到 3 |
| reply 說「資料庫裡沒有這個資訊」 | 問題超出知識文件範圍 | 這是正確行為；上傳相關文件或改用 `/chat` |

---

## 費用

| 資源 | 費用 |
|------|------|
| S3 bucket（3 個小文字檔） | < $0.001/月 |
| S3 GET 請求（每次 /rag 約 3 次） | < $0.001/1000 次請求 |
| Bedrock Converse（依 token 計費） | nova lite: ~$0.0002/次；deepseek: ~$0.002/次 |
| **合計** | 幾乎免費 |

---

## 與正式 RAG 的差距

Poor Man's RAG 沒有做的事，以及對應的升級方向：

| 缺少的功能 | 升級方向 |
|-----------|---------|
| Semantic search（語意搜尋） | pgvector（Aurora PostgreSQL）+ embedding |
| 大型知識庫（> context window） | Bedrock Knowledge Bases（托管 RAG） |
| 文件格式支援（PDF、Word） | Bedrock Data Source（自動解析） |
| 即時更新 | S3 Event Notification → Lambda → re-embed |
| Reranking | 加一層 cross-encoder 篩 Top-K |

---

*紀錄日期：2026-06-22*
*環境：AWS EKS 1.36 / custom-app v7 / Bedrock Converse API / aws-sdk-go-v2*
