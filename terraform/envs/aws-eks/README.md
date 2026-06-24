# AWS EKS Lab — EKS + ALB + ECR + ArgoCD + IRSA + Bedrock + RAG

完整 Kubernetes 練習環境，從基礎 EKS 一路玩到 GitOps、IRSA、Bedrock LLM、RAG、可觀測性。

> 💰 **費用等級：🔴 危險** — ~$0.25/hr（3 節點 + 4 ALB），用完立刻 `terraform destroy`！

---

## 費用估算

| 資源 | 規格 | 費用 |
|------|------|------|
| EKS Control Plane | 固定 | $0.10/hr |
| t3.medium SPOT × 3 | 節點（monitoring 後需 3 台） | ~$0.042/hr |
| NAT Gateway | 1 AZ | $0.045/hr |
| ALB × 4 | custom-app / podinfo / monitoring / argocd | ~$0.064/hr |
| EBS gp2 20GB × 3 | 磁碟 | ~$0.006/hr |
| S3 | RAG knowledge base | ~$0 |
| ECR | image 儲存 | ~$0 |
| **合計** | | **~$0.257/hr** |

**省錢技巧：** 不用時把 Node Group scale to 0（EKS CP + NAT GW 還是燒，但節省節點費用）：
```bash
aws eks update-nodegroup-config \
  --cluster-name infra-lab-dev-eks \
  --nodegroup-name infra-lab-dev-nodes \
  --scaling-config minSize=0,maxSize=3,desiredSize=0 \
  --region us-east-1
```

---

## 架構

```
Custom VPC (10.0.0.0/16)
│
├── Public Subnets (10.0.1.0/24, 10.0.2.0/24)
│   ├── Internet Gateway
│   ├── NAT Gateway (Elastic IP: 54.197.156.188)
│   └── ALB × 4（由 AWS Load Balancer Controller 自動建立）
│       ├── eks-demo      → custom-app (v7)
│       ├── eks-podinfo   → podinfo
│       ├── eks-monitoring → Grafana
│       └── eks-argocd    → ArgoCD UI
│
└── Private Subnets (10.0.11.0/24, 10.0.12.0/24)
    └── EKS Managed Node Group (3x t3.medium SPOT)
        │
        ├── argocd/          ArgoCD GitOps controller
        ├── custom-app/      Go HTTP service (IRSA + Bedrock + RAG + /metrics)
        ├── podinfo/         參考微服務
        └── monitoring/      Prometheus + Grafana + node-exporter

ECR: infra-lab-dev-app (v3 → v7)
S3:  infra-lab-dev-rag-661515655645 (RAG knowledge base)
IAM: infra-lab-dev-custom-app-role (IRSA: S3 + Bedrock)
```

---

## 實戰 Labs

| 文件 | 主題 | 涉及的 AWS 服務 |
|------|------|----------------|
| [irsa-demo.md](./docs/irsa-demo.md) | IRSA + S3 + Bedrock Converse API | IAM / STS / S3 / Bedrock |
| [rag-demo.md](./docs/rag-demo.md) | Poor Man's RAG — S3 知識庫 + Bedrock | S3 / Bedrock |
| [monitoring-demo.md](./docs/monitoring-demo.md) | kube-prometheus-stack 可觀測性 | — |
| [argocd-demo.md](./docs/argocd-demo.md) | ArgoCD GitOps + ALB Ingress | ALB / ALB Controller |
| [gitops-cicd-demo.md](./docs/gitops-cicd-demo.md) | GitHub Actions OIDC → ECR → ArgoCD CD Pipeline | IAM / ECR / GitHub Actions |
| [eso-demo.md](./docs/eso-demo.md) | External Secrets Operator — Secrets Manager → K8s Secret | Secrets Manager / IAM / ESO |
| [secret-rotation-demo.md](./docs/secret-rotation-demo.md) | Secrets Manager 自動 Rotation — Lambda 4-step protocol | Secrets Manager / Lambda |
| [argo-rollouts-demo.md](./docs/argo-rollouts-demo.md) | Argo Rollouts Canary — ALB 流量切換 + Prometheus 自動分析 | Argo Rollouts / ALB / Prometheus |
| [cleanup.md](./docs/cleanup.md) | 完整清除步驟 — 正確順序與卡住時的手動處理 | — |
| [hpa-demo.md](./docs/hpa-demo.md) | Horizontal Pod Autoscaler | — |
| [bedrock-irsa-403-fix.md](./docs/bedrock-irsa-403-fix.md) | Bedrock cross-region inference profile 403 修正 | Bedrock / IAM |

---

## 快速開始

### 1. Terraform Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# 視需要修改 region / project

terraform init
terraform fmt && terraform validate
terraform plan
terraform apply   # 約 20-25 分鐘

# 設定 kubectl
$(terraform output -raw kubeconfig_command)

# 驗證節點
kubectl get nodes -o wide
```

### 2. 安裝 AWS Load Balancer Controller

```bash
$(terraform output -raw aws_lbc_helm_command)

kubectl rollout status deployment/aws-load-balancer-controller -n kube-system
```

### 3. 安裝 ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace

kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

# 套用 ALB Ingress + --insecure 設定
kubectl apply -f k8s/argocd/argocd-insecure-cm.yaml
kubectl rollout restart deployment/argocd-server -n argocd
kubectl apply -f k8s/argocd/argocd-ingress.yaml

# 取得初始密碼
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

### 4. 套用 ArgoCD Applications

```bash
kubectl apply -f k8s/argocd/custom-app-app.yaml
kubectl apply -f k8s/argocd/podinfo-app.yaml
kubectl apply -f k8s/argocd/monitoring-app.yaml

# 建立 Grafana admin secret（monitoring 部署前必做）
kubectl create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=<你的密碼> \
  -n monitoring
```

### 5. 建立 custom-app 所需 Secret

```bash
# Bedrock /chat + /rag 的 API Key
kubectl create secret generic custom-app-secrets \
  --from-literal=chat-api-key=$(openssl rand -hex 20) \
  -n custom-app
```

### 6. IRSA + RAG Terraform 資源

```bash
# 建立 S3 knowledge base + IAM policy
terraform apply \
  -target=aws_s3_bucket.rag_knowledge \
  -target=aws_s3_bucket_public_access_block.rag_knowledge \
  -target=aws_iam_role_policy.custom_app_s3_rag \
  -target=aws_s3_object.infra_lab_overview \
  -target=aws_s3_object.irsa_guide \
  -target=aws_s3_object.bedrock_models
```

### 7. Build + Push custom-app

```bash
$(terraform output -raw ecr_login_command)

cd app/
docker build -t infra-lab-dev-app:v7 .
docker tag infra-lab-dev-app:v7 \
  $(terraform output -raw ecr_repository_url):v7
docker push $(terraform output -raw ecr_repository_url):v7
```

---

## 現有服務 URL

```bash
# custom-app（IRSA + Bedrock + RAG + metrics）
kubectl get ingress custom-app -n custom-app \
  -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}'

# podinfo
kubectl get ingress -n podinfo \
  -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}'

# Grafana（帳號: admin）
kubectl get ingress -n monitoring \
  -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}'

# ArgoCD（帳號: admin）
kubectl get ingress argocd-server -n argocd \
  -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}'
```

---

## 驗證清單

```bash
# 節點
kubectl get nodes -L eks.amazonaws.com/capacityType

# 所有 namespace
kubectl get pods -A | grep -v Running

# ArgoCD Applications
kubectl get applications -n argocd

# custom-app endpoints
ALB=$(kubectl get ingress custom-app -n custom-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$ALB/           # App info
curl http://$ALB/aws        # S3 via IRSA
curl http://$ALB/metrics    # Prometheus metrics
curl "http://$ALB/chat?q=hello&model=nova" -H "X-API-Key: <key>"
curl "http://$ALB/rag?q=what+is+IRSA&model=nova" -H "X-API-Key: <key>"
```

---

## 用完砍掉

```bash
# 先清 Ingress（避免 ALB/SG 擋住 destroy）
kubectl delete ingress --all -A

# 砍全部（約 15 分鐘）
terraform destroy -auto-approve
```

---

## 卡關提示

| 症狀 | 原因 | 解法 |
|------|------|------|
| `apply` 卡在 EKS | 正常，EKS + NAT GW 需要 20-25 分鐘 | 等待 |
| 節點一直 `NotReady` | VPC CNI 初始化中 | 等 3-5 分鐘 |
| `kubectl` 連不到 | kubeconfig 過期 | 重跑 `aws eks update-kubeconfig` |
| ALB 沒建立 | LBC 未就緒或 subnet tag 缺少 | 確認 LBC 正常、subnet 有 `kubernetes.io/role/elb=1` |
| Pod `Pending`（Too many pods） | 節點資源不足 | Node Group desiredSize 加到 3 |
| ArgoCD UI 無法開啟 | redirect loop | 確認 `argocd-cmd-params-cm` 有 `server.insecure: "true"` |
| Bedrock 403 | inference profile ARN 未授權 | 見 [bedrock-irsa-403-fix.md](./docs/bedrock-irsa-403-fix.md) |
| `destroy` 卡住 | ALB 未刪乾淨 | 先 `kubectl delete ingress --all -A` |
