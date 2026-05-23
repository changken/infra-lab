# Lab 15: EKS Cluster

建立 Kubernetes 控制平面與 Managed Node Group，用 kubectl 操作第一個 EKS 叢集。
**費用等級 🔴 危險** — EKS 控制平面 $0.10/hr，**同一天完成後立刻 destroy**。

## 學習目標

- **兩個 IAM Role**：Cluster Role（`eks.amazonaws.com`）vs Node Role（`ec2.amazonaws.com`），Principal 不同，功能不同
- `aws_eks_cluster`：定義 Kubernetes 控制平面，`vpc_config.subnet_ids` 決定節點可跑的網段
- `aws_eks_node_group`：Managed Node Group，AWS 自動管理 EC2 工作節點生命週期
- `scaling_config`：`desired_size / min_size / max_size` 三個參數
- `depends_on`：EKS 資源有嚴格的 IAM 依賴，缺少會導致 apply 失敗
- `aws eks update-kubeconfig`：apply 後設定 kubectl 存取叢集

## 架構

```
┌─────────────────────────────────────────────────┐
│  AWS EKS Control Plane（$0.10/hr）              │
│  Kubernetes API Server                           │
│  Role: eks-lab-cluster-role                      │
│        Principal: eks.amazonaws.com              │
└──────────────────┬──────────────────────────────┘
                   │ manages
┌──────────────────▼──────────────────────────────┐
│  Managed Node Group                              │
│  t3.medium × 2（desired）                        │
│  Role: eks-lab-node-role                         │
│        Principal: ec2.amazonaws.com              │
│  Policies: EKSWorkerNodePolicy                   │
│            EKS_CNI_Policy                        │
│            EC2ContainerRegistryReadOnly          │
└─────────────────────────────────────────────────┘
```

## 你要做的事

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_iam_role.cluster` + `aws_iam_role_policy_attachment.cluster` | trust **eks.amazonaws.com**，AmazonEKSClusterPolicy |
| 2 | `aws_iam_role.node` | trust **ec2.amazonaws.com**（三個 policy attachment 已預填）|
| 3 | `aws_eks_cluster.main` | `vpc_config.subnet_ids`，`depends_on` cluster role attachment |
| 4 | `aws_eks_node_group.main` | `scaling_config`，`depends_on` 三個 node policy attachments |

已預填：data sources、三個 Node policy attachments

## 指令

### Step 1：填寫 TODOs 並建立資源

```bash
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 不需要修改，預設值即可

terraform init
terraform fmt
terraform validate
terraform plan    # 預期：8 to add
terraform apply   # EKS 控制平面啟動需 10-15 分鐘，請耐心等候
```

### Step 2：設定 kubectl

```bash
# 取得 kubeconfig 指令（terraform 已輸出）
terraform output kubeconfig_command

# 執行該指令（範例）
aws eks update-kubeconfig --region us-east-1 --name eks-lab
```

**Windows PowerShell：**
```powershell
$cmd = terraform output -raw kubeconfig_command
Invoke-Expression $cmd
```

### Step 3：驗證

```bash
# 確認節點已加入 cluster（節點 Ready 可能需要 3-5 分鐘）
kubectl get nodes

# 預期輸出（2 個節點 Ready）：
# NAME                          STATUS   ROLES    AGE   VERSION
# ip-172-31-xx-xx.ec2.internal  Ready    <none>   2m    v1.31.x
# ip-172-31-yy-yy.ec2.internal  Ready    <none>   2m    v1.31.x

# 確認叢集資訊
kubectl cluster-info

# 查看所有系統 Pod
kubectl get pods -n kube-system
```

**也可以用 AWS CLI 驗證：**
```bash
# 確認 cluster status = ACTIVE
aws eks describe-cluster --name eks-lab --query "cluster.status"

# 列出 node group
aws eks list-nodegroups --cluster-name eks-lab
```

### 結束

```bash
# ⚠️ EKS 控制平面 $0.10/hr，務必立刻 destroy！
terraform destroy -auto-approve
# destroy 需要 10-15 分鐘（節點先縮為 0，再刪 cluster）
```

## 成本

| 資源 | 費用 |
|------|------|
| EKS Control Plane | $0.10/hr |
| t3.medium × 2（工作節點）| $0.094/hr（$0.047 × 2）|
| EBS（30 GB × 2 nodes）| $0.007/hr |
| **3 小時 Lab 合計** | **~$0.60** |

**EKS 是這個路線圖中最貴的 Lab，一日 Sprint 絕對不能過夜（$0.20 × 24 = $4.80/天）。**

## IAM Role 說明

EKS 需要兩個不同的 IAM Role，這是 EKS 最容易搞混的概念：

| Role | Principal | 用途 | Policy |
|------|-----------|------|--------|
| Cluster Role | `eks.amazonaws.com` | 控制平面管理 VPC、ELB、IAM | AmazonEKSClusterPolicy |
| Node Role | `ec2.amazonaws.com` | 工作節點加入 cluster、拉 ECR image、配置 Pod 網路 | 3 個（必須全填）|

Node 的三個 policy 缺一不可：
- `AmazonEKSWorkerNodePolicy`：允許節點加入 EKS cluster
- `AmazonEKS_CNI_Policy`：允許 vpc-cni 配置 Pod IP（缺少時 Pod 無法啟動）
- `AmazonEC2ContainerRegistryReadOnly`：允許拉 ECR image

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `apply` 失敗：`InvalidParameterException: Role is not assumable` | Cluster Role 的 `assume_role_policy` 寫錯，Principal 應為 `eks.amazonaws.com` |
| 節點一直不 Ready（`kubectl get nodes` 空白）| Node Role 的三個 policy attachment 沒設完，尤其是 `AmazonEKS_CNI_Policy` |
| `kubectl` 連不上：`Unable to connect to the server` | 忘了執行 `aws eks update-kubeconfig`，或 region/name 打錯 |
| `terraform plan` 出現 `depends_on` 警告 | 正常，EKS 資源需要顯式依賴 |
| destroy 卡住很久 | 正常，EKS 先縮節點再刪 cluster，需要 10-15 分鐘 |
| `InvalidParameterException: Kubernetes 1.31 is no longer supported` | 更新 `kubernetes_version` 到當前支援版本（見 [EKS 版本文件](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)）|
