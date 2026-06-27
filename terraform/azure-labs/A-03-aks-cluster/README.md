# A-03：AKS Cluster 基礎 🔴 > $1/hr

> 用 Terraform 建立 AKS cluster，對比你已熟悉的 EKS（lab 15-16）。

**費用估算**：Standard_B2s × 1 node ≈ $0.048/hr → **一日 Sprint，當天 destroy**

---

## 學習目標

- 理解 AKS vs EKS 的建立方式差異（一個資源 vs 兩個資源）
- 用 `az aks get-credentials` 取得 kubeconfig（對比 `aws eks update-kubeconfig`）
- 學習 AKS Managed Identity（對比 EKS 的 EC2 Instance Profile）
- 啟用 OIDC issuer 為 A-04 Workload Identity 做準備
- 選填：串接 A-02 ACR，讓 AKS node 免帳密拉 image

## AWS vs Azure 對比

| 元素 | AWS (Lab 15-16) | Azure (本 Lab) |
|------|----------------|---------------|
| Cluster 資源 | `aws_eks_cluster` | `azurerm_kubernetes_cluster` |
| Node Group 資源 | `aws_eks_node_group`（獨立） | `default_node_pool`（內嵌在 cluster） |
| Cluster 身份 | IAM Role | SystemAssigned Managed Identity |
| Node 身份 | EC2 Instance Profile | Kubelet Managed Identity |
| kubeconfig | `aws eks update-kubeconfig` | `az aks get-credentials` |
| Registry 授權 | IAM Policy AmazonECRReadOnly | RBAC AcrPull Role Assignment |
| OIDC | `aws_iam_openid_connect_provider` 手動建 | `oidc_issuer_enabled = true` 一行搞定 |
| Apply 時間 | ~15 分鐘 | ~8 分鐘 |

## 架構

```
┌──────────────────────────────────────────┐
│  AKS Cluster                              │
│  ┌────────────────────────────────────┐  │
│  │  System Node Pool                  │  │
│  │  Standard_B2s × 1 node             │  │
│  │  Kubelet Managed Identity ──────────┼──┼──► AcrPull → ACR (A-02)
│  └────────────────────────────────────┘  │
│  OIDC Issuer（為 A-04 Workload Identity） │
└──────────────────────────────────────────┘
        Resource Group
```

## 你要做的事

| TODO | 資源 | 說明 |
|------|------|------|
| TODO 1 | `azurerm_resource_group` | 資源容器 |
| TODO 2 | `azurerm_kubernetes_cluster` | Cluster + node pool + identity + OIDC |
| TODO 3 | `azurerm_role_assignment` | AcrPull（選填，acr_id 有值才建） |
| outputs | 5 個 output | cluster_name、kube_config_cmd、oidc_issuer_url 等 |

## 操作步驟

```bash
# 1. 複製並填寫變數
cp terraform.tfvars.example terraform.tfvars

# 2. 部署（需要 5-10 分鐘）
terraform init
terraform fmt && terraform validate
terraform plan
terraform apply

# 3. 取得 kubeconfig（對比 aws eks update-kubeconfig）
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw cluster_name)

# 確認連線
kubectl get nodes
kubectl get pods -A
```

## 驗證

```bash
# 確認 node 狀態
kubectl get nodes -o wide

# 部署測試 workload
kubectl create deployment nginx --image=nginx --replicas=1
kubectl get pods

# 確認 OIDC issuer URL（A-04 會用到）
terraform output oidc_issuer_url

# 清理測試 workload
kubectl delete deployment nginx
```

## 清除資源

```bash
# ⚠️ 完成後務必 destroy，B2s node 持續計費
terraform destroy -auto-approve

# 順便清掉 kubeconfig 中的 AKS context
kubectl config delete-context $(terraform output -raw cluster_name)
```

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `node_count` 無法設定 | `enable_auto_scaling = false` 時才能用 `node_count`，預設即可 |
| apply 報 quota 錯誤 | Student 訂閱有 vCPU 配額限制，換 `eastasia` region 或縮小 VM size |
| `kubectl get nodes` 連不上 | 確認有執行 `az aks get-credentials`，或 `KUBECONFIG` 路徑正確 |
| AcrPull assignment 失敗 | `azurerm_role_assignment` 需要 `count`，acr_id 為 null 時不能 evaluate scope |
| OIDC URL 是空的 | `oidc_issuer_enabled = true` 忘記加，需 destroy 重建 |
