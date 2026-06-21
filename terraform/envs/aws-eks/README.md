# AWS EKS + ALB + ECR + ArgoCD

完整 Kubernetes 練習環境：EKS + AWS Load Balancer Controller + ECR + ArgoCD GitOps。

> 💰 **費用等級：🔴 危險** — ~$0.18/hr，用完立刻 `terraform destroy`！
> ⚠️ 9 天全開 ≈ $39（超過 $37 credit），建議不用時先 destroy。

---

## 費用估算

| 資源 | 規格 | 費用 |
|------|------|------|
| EKS Control Plane | 固定 | $0.10/hr |
| t3.medium SPOT × 2 | 節點 | ~$0.028/hr |
| NAT Gateway | 1 AZ | $0.045/hr |
| ALB | ~$0.008/hr + LCU | ~$0.01/hr |
| EBS gp2 20GB × 2 | 磁碟 | ~$0.004/hr |
| ECR | ~$0.10/GB/月 | 幾乎免費 |
| **合計** | | **~$0.187/hr** |

一日 Sprint 8 小時 ≈ **$1.50**

---

## 架構

```
Custom VPC (10.0.0.0/16)
│
├── Public Subnets (10.0.1.0/24, 10.0.2.0/24)
│   ├── Internet Gateway
│   ├── NAT Gateway (Elastic IP)
│   └── ALB ← 由 AWS Load Balancer Controller 自動建立
│
└── Private Subnets (10.0.11.0/24, 10.0.12.0/24)
    └── EKS Managed Node Group
        ├── t3.medium SPOT (node-1, us-east-1a)
        └── t3.medium SPOT (node-2, us-east-1b)
            ├── ArgoCD
            └── Your App → Ingress → ALB

ECR Repository: infra-lab-dev-app
```

---

## 步驟 1：Terraform Apply

```bash
# 1. 複製 tfvars
cp terraform.tfvars.example terraform.tfvars

# 2. (選填) 修改 region / project

# 3. Init + Apply（約 20-25 分鐘）
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply

# 4. 設定 kubectl
$(terraform output -raw kubeconfig_command)

# 5. 驗證節點（應有 2 個 Ready）
kubectl get nodes -o wide
```

---

## 步驟 2：安裝 AWS Load Balancer Controller

```bash
# 複製並執行 Terraform output 的 Helm 指令
terraform output -raw aws_lbc_helm_command

# 等待 LBC 啟動
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system

# 確認 LBC 正常運作
kubectl get deployment -n kube-system aws-load-balancer-controller
```

---

## 步驟 3：安裝 ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 等待啟動
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# 取得 admin 密碼
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Port-forward（本機測試用）
kubectl port-forward svc/argocd-server -n argocd 8080:443
# 開啟 https://localhost:8080（帳號: admin）

# 或建立 Ingress（讓 ALB 公開 ArgoCD）
# 見下方 "ALB Ingress 範例"
```

---

## 步驟 4：推 Image 到 ECR

```bash
# 登入 ECR
$(terraform output -raw ecr_login_command)

# 設定 repo URL
REPO=$(terraform output -raw ecr_repository_url)

# Build + Push
docker build -t my-app:v1 .
docker tag my-app:v1 $REPO:v1
docker push $REPO:v1
```

---

## ALB Ingress 範例

建立 Ingress 後，AWS LBC 會自動建立 ALB：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app-svc
            port:
              number: 80
```

```bash
# 套用後取得 ALB DNS
kubectl get ingress my-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## 驗證清單

```bash
# 節點（應有 2 個 Ready、SPOT 標籤）
kubectl get nodes -L node.kubernetes.io/instance-type,eks.amazonaws.com/capacityType

# AWS LBC
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# ArgoCD
kubectl get pods -n argocd

# ECR images
aws ecr list-images --repository-name infra-lab-dev-app --region us-east-1
```

---

## 用完砍掉

```bash
# 先清 K8s 資源（避免 ALB/SG 被 LBC 擋住 destroy）
kubectl delete ingress --all -A
kubectl delete namespace argocd --ignore-not-found
kubectl delete namespace my-app --ignore-not-found

# 砍全部（約 15 分鐘）
terraform destroy -auto-approve
```

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `apply` 卡在 EKS | 正常，EKS + NAT GW 需要 20-25 分鐘 |
| 節點一直 `NotReady` | 等 3-5 分鐘讓 VPC CNI 初始化 |
| `kubectl` 連不到 | 重跑 `aws eks update-kubeconfig` |
| ALB 沒建立 | 確認 LBC 正常、subnet 有 `kubernetes.io/role/elb=1` tag |
| ECR push 403 | 重跑 ECR 登入指令 |
| SPOT 節點被回收 | ASG 自動補，等 1-2 分鐘 |
| `destroy` 卡住 | ALB 未刪乾淨，先 `kubectl delete ingress --all -A` |
| `aws_lbc_version` IAM policy 404 | 更新 `aws_lbc_version` 到最新版本 |
