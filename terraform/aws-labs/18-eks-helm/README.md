# Lab 18: EKS Helm

用 Terraform Helm Provider 將現成 Chart 部署到 EKS，體驗 `helm_release` 與 `set {}` 客製化 chart values。
**費用等級 🔴 危險** — 需搭配 Lab 15 的 EKS Cluster，ELB 額外 $0.008/hr，**當天完成後連同 Lab 15 一起 destroy**。

**前置條件**：Lab 15 的 EKS Cluster 必須是 `ACTIVE` 狀態，且 `kubectl get nodes` 顯示節點 `Ready`。

## 學習目標

- **Helm Provider** 設定：與 Kubernetes Provider 相同連線資訊，但結構用 `kubernetes {}` 子 block
- `helm_release`：Terraform 管理 Helm Release 的生命週期（install / upgrade / uninstall）
- `set {}` block：覆寫 Chart values（等同於 `helm install --set key=value`）
- `create_namespace = true`：讓 Helm 自動建立 namespace
- 理解 Helm Repository URL 的作用

## 部署的 Chart

| Chart | 用途 | Namespace |
|-------|------|-----------|
| metrics-server | 提供 `kubectl top` 節點/Pod 資源使用量 | kube-system |
| ingress-nginx | Ingress Controller，自動建立 ELB | ingress-nginx |

## 架構

```
Internet（port 80/443）
    ↓
AWS NLB（由 ingress-nginx Helm Chart 自動建立）
    ↓
Ingress Controller Pod（ingress-nginx）
    ↓ 根據 Ingress 規則轉發
應用 Pod

另外：
metrics-server Pod（kube-system）
    ← 提供 kubectl top nodes / kubectl top pods 資料
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `helm_release.metrics_server` | 基本 helm_release，`set {}` 加 `--kubelet-insecure-tls`（EKS 必要）|
| 2 | `helm_release.ingress_nginx` | 多個 `set {}` blocks，`create_namespace = true`，注意 `.` 跳脫 |

已預填：EKS data sources、Kubernetes + Helm provider 設定

## Helm Release 結構說明

```hcl
resource "helm_release" "example" {
  name       = "release-name"    # helm install <name>
  repository = "https://..."     # helm repo add 的 URL
  chart      = "chart-name"      # repo 中的 chart 名稱
  namespace  = "target-ns"       # 安裝到哪個 namespace
  version    = "x.y.z"          # chart version（建議鎖定）
  create_namespace = true        # namespace 不存在時自動建立

  # 等同於 helm install ... --set controller.replicaCount=1
  set {
    name  = "controller.replicaCount"
    value = "1"
  }
}
```

**`set.name` 中的 `.` 跳脫規則：**  
Annotation key（如 `service.beta.kubernetes.io/aws-load-balancer-type`）中的 `.` 在 Terraform 中需寫成 `\\.`，否則 Helm 會誤解為 value 路徑的分隔符號。

## 指令

### 前置確認（Lab 15 必須已 apply）

```bash
aws eks describe-cluster --name eks-lab --query "cluster.status"
kubectl get nodes
```

### Step 1：填寫 TODOs 並部署

```bash
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：2 to add
terraform apply   # 約 3-5 分鐘（Helm 需要等待 Pod 就緒）
```

### Step 2：驗證

```bash
# 驗證 metrics-server（稍等約 1 分鐘讓 metrics-server 收集數據）
kubectl top nodes
# 預期：節點的 CPU / Memory 用量

kubectl top pods -A
# 預期：所有 namespace 的 Pod 資源用量

# 驗證 ingress-nginx（ELB 分配需要 1-2 分鐘）
kubectl get svc -n ingress-nginx ingress-nginx-controller
# 預期：EXTERNAL-IP 欄位出現 ELB hostname

# 查看所有 Helm Release
helm list -A
# 預期：metrics-server（kube-system）、ingress-nginx（ingress-nginx）
```

**快速驗證 ingress-nginx：**
```bash
INGRESS_HOST=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$INGRESS_HOST
# 預期：404 Not Found（表示 ingress controller 在跑，只是沒有 Ingress 規則）
```

### 結束

```bash
terraform destroy -auto-approve

cd ../15-eks-cluster
terraform destroy -auto-approve
```

## 成本

| 資源 | 費用 |
|------|------|
| EKS Control Plane（Lab 15）| $0.10/hr |
| t3.medium × 2 工作節點（Lab 15）| $0.094/hr |
| NLB（ingress-nginx 建立）| $0.008/hr + LCU |
| **3 小時 Lab 合計** | **~$0.61** |

## helm vs kubectl apply vs Terraform kubernetes_*

| 方式 | 適用場景 | 優點 | 缺點 |
|------|---------|------|------|
| `kubectl apply -f` | 快速測試 | 直接 | 不受 Terraform 管理 |
| `kubernetes_*` (Lab 16) | 簡單自定義 app | 與 Terraform 狀態整合 | 需手動定義每個資源 |
| `helm_release` (本 Lab) | 複雜第三方 app | Chart 封裝複雜度 | 需了解 Chart values |

Helm 最適合部署「需要很多 K8s 資源、有很多客製化選項」的第三方套件（如 ingress, prometheus, cert-manager）。

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `kubectl top nodes` 顯示 `error: metrics not available yet` | metrics-server 剛啟動，等 1-2 分鐘 |
| `kubectl top nodes` 一直 `error: Metrics API not available` | `--kubelet-insecure-tls` 沒加到 metrics-server 的 args |
| ingress-nginx Pod 一直 `Pending` | 節點資源不足（2 個 t3.medium 應足夠，確認 `kubectl describe pod`）|
| `terraform apply` timeout（等超過 10 分鐘）| Helm 預設等待 Pod Ready，若節點資源不足會卡住 |
| Chart version not found | `metrics_server_version` 或 `ingress_nginx_version` 版本不存在，到 ArtifactHub 查詢最新版 |
| annotation `set.name` 格式錯誤 | annotation key 中的 `.` 必須改寫成 `\\.` |
