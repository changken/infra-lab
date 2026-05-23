# Lab 16: EKS Workloads

用 Terraform 的 Kubernetes Provider 將應用程式部署到 EKS，體驗 K8s 的 Deployment + LoadBalancer Service。
**費用等級 🔴 危險** — 需搭配 Lab 15 的 EKS Cluster，合計約 **$0.21/hr**，當天完成後連同 Lab 15 一起 destroy。

**前置條件**：Lab 15 的 EKS Cluster 必須是 `ACTIVE` 狀態，且 `kubectl get nodes` 顯示節點 `Ready`。

## 學習目標

- **Kubernetes Terraform Provider**：用 Terraform 管理 K8s 資源，等同於 `kubectl apply -f`
- `kubernetes_namespace`：K8s 命名空間，資源隔離的基本單位
- `kubernetes_deployment`：定義 Pod 期望狀態（image, replicas, port），理解三層巢狀結構（spec → template → spec → container）
- `kubernetes_service` (type=LoadBalancer)：讓 K8s 控制器自動建立 AWS ELB 對外暴露服務
- `selector` / `match_labels`：Deployment 與 Service 之間的「黏合劑」

## 架構

```
Internet（port 80）
    ↓
AWS ELB（由 K8s Service 自動建立）
    ↓ selector: app=eks-workloads
Kubernetes Service（LoadBalancer）
    ↓ 
Pod × 2（nginx:alpine, port 80）
    ← Kubernetes Deployment 管理生命週期
    ← 部署在 namespace: demo
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `kubernetes_namespace.app` | `metadata.name = var.namespace_name`，用 labels 不用 tags |
| 2 | `kubernetes_deployment.app` | `selector.match_labels` 必須和 `template.metadata.labels` 一致 |
| 3 | `kubernetes_service.app` | `type = "LoadBalancer"`，`selector` 對應 Deployment labels |

已預填：EKS data sources（`aws_eks_cluster` + `aws_eks_cluster_auth`）、Kubernetes provider 設定

## 指令

### 前置確認（Lab 15 必須已 apply）

```bash
# 確認 cluster 存在
aws eks describe-cluster --name eks-lab --query "cluster.status"
# 預期輸出：ACTIVE

# 確認 kubeconfig 已設定
kubectl get nodes
# 預期：2 個節點 Ready
```

### Step 1：填寫 TODOs 並部署

```bash
cp terraform.tfvars.example terraform.tfvars
# 確認 cluster_name 與 Lab 15 的 project 名稱一致

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：3 to add（namespace, deployment, service）
terraform apply
```

### Step 2：驗證

```bash
# 取得 ELB URL（ELB 分配需要 1-2 分鐘）
terraform output service_url

# 等待 ELB 就緒後 curl 測試
curl http://<ELB_HOSTNAME>
# 預期：nginx 歡迎頁（HTML）

# 也可以用 kubectl 驗證
kubectl get all -n demo
# 預期：deployment (2/2 ready), service (有 EXTERNAL-IP)
```

**kubectl 詳細驗證：**
```bash
# 查看 Pod 狀態
kubectl get pods -n demo

# 查看 Service 的 ELB hostname
kubectl get svc -n demo

# 查看 Deployment 詳細資訊
kubectl describe deployment eks-workloads-app -n demo
```

### 結束

```bash
# 先 destroy 本 lab 的 K8s 資源（會刪除 ELB）
terraform destroy -auto-approve

# 再回到 Lab 15 destroy EKS cluster（順序很重要！）
cd ../15-eks-cluster
terraform destroy -auto-approve
```

## 成本

| 資源 | 費用 |
|------|------|
| EKS Control Plane（Lab 15）| $0.10/hr |
| t3.medium × 2 工作節點（Lab 15）| $0.094/hr |
| ELB（LoadBalancer Service）| $0.008/hr + LCU |
| **3 小時 Lab 合計** | **~$0.61** |

## Kubernetes Terraform Provider 說明

本 Lab 使用 `data.aws_eks_cluster` + `data.aws_eks_cluster_auth` 連接到已存在的 EKS cluster：

```hcl
provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}
```

這個模式是 EKS + Terraform 的標準做法。`cluster_ca_certificate` 是 Base64 編碼，需要 `base64decode()` 解碼。

## Deployment 三層巢狀結構

K8s Deployment 的 HCL 結構容易讓初學者搞混，記住這個層次：

```
kubernetes_deployment
  └── spec (Deployment spec)
        ├── replicas
        ├── selector.match_labels  ← 必須和下面的 labels 一致！
        └── template
              ├── metadata.labels  ← 必須和上面的 match_labels 一致！
              └── spec (Pod spec)
                    └── container
                          ├── name
                          ├── image
                          └── port.container_port
```

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `init` 失敗：`Error: Failed to configure Kubernetes provider` | Lab 15 的 cluster 尚未 ACTIVE，或 `cluster_name` 設定錯誤 |
| `apply` 後 `kubectl get pods` 顯示 `Pending` | 節點資源不足（t3.medium 應能跑 2 個 nginx），查看 `kubectl describe pod <name> -n demo` |
| `service_url` 輸出空字串 | ELB 還在分配（等 1-2 分鐘後再 `terraform output`） |
| `curl` 回應 `Connection refused` | ELB 已分配但 Pod 還沒 Ready，等 Pod Running 後再試 |
| `selector` 相關 error | `match_labels` 和 `template.metadata.labels` 的 key/value 不一致 |
| destroy 順序錯誤（先刪 Lab 15）| ELB 孤立在 VPC 中導致 Lab 15 destroy 卡住，需手動刪 ELB |
