# Karpenter Lab — 自動節點佈建

> 費用等級 🔴 | EKS Control Plane $0.10/hr，Lab 完成後立即 `terraform destroy`

---

## 概念

### Managed Node Group vs Karpenter

```
Managed Node Group（原有架構）
  ASG 設定 min=1 max=3
    └── t3.medium × N（指定機型）
          └── HPA 調整 Pod 數量
                └── Node 不夠？需要額外安裝 Cluster Autoscaler 才能加 Node

Karpenter（本 Lab）
  Pending Pod（排程失敗）
    └── Karpenter 偵測 → 計算需要什麼資源
          └── 選最便宜/最合適的機型（bin-packing，53+ 候選機型）
                └── EC2 API 啟動 → Node 60秒內加入 cluster
```

### 為什麼 Karpenter 省錢？

1. **Bin-packing**：每個 Pod 按實際 request 計算，選最小夠用的機型
2. **即時選型**：不鎖定單一機型，SPOT 池子更大，中斷機率更低
3. **主動縮容**：節點閒置後自動 consolidate（搬 Pod 到更少節點）

### SQS 中斷處理流程

```
AWS 決定回收 SPOT 機器
  └── 發送事件到 EventBridge（提前 2 分鐘）
        └── EventBridge Rule → SQS Queue
              └── Karpenter 消費訊息
                    └── cordon Node（不排新 Pod）
                          └── drain Node（優雅驅逐 Pod）
                                └── Pod 搬到其他 Node → 服務不中斷
```

---

## 架構

```
                      ┌─────────────────┐
                      │  EventBridge    │
    AWS Events        │  Rules (4種)    │
  ┌──────────────┐   │                 │
  │ SPOT Warning │──►│ spot-interrupt  │
  │ Rebalance   │──►│ rebalance       │──► SQS Queue
  │ StateChange │──►│ instance-state  │   karpenter-interruption
  │ Health      │──►│ health          │
  └──────────────┘   └─────────────────┘
                              │
                              ▼
    ┌─────────────────────────────────────────────┐
    │ EKS Cluster                                 │
    │                                             │
    │  karpenter (namespace)                      │
    │    └── Karpenter Controller ←── IRSA Role   │
    │          ├── watches: Pending Pods           │
    │          ├── calls: EC2 API (launch/term)   │
    │          └── reads: SQS interruption events │
    │                                             │
    │  Managed Node Group (system nodes)          │
    │    └── kube-system, argocd, monitoring      │
    │                                             │
    │  Karpenter Nodes (workload nodes, dynamic)  │
    │    └── custom-app, podinfo, ...             │
    └─────────────────────────────────────────────┘
```

---

## Terraform 資源清單

| 資源 | 說明 |
|------|------|
| `aws_iam_role.karpenter_node` | Karpenter 啟動的 Node 用的 IAM Role（獨立於 MNG） |
| `aws_iam_role.karpenter` | Controller IRSA Role（讓 Pod 呼叫 EC2/SQS API） |
| `aws_iam_policy.karpenter` | Controller 所需的完整 EC2/IAM/SQS/EKS 權限 |
| `aws_sqs_queue.karpenter_interruption` | 接收 SPOT 中斷通知的 Queue |
| `aws_cloudwatch_event_rule.*` | 4 種 EventBridge Rules → SQS |
| `aws_eks_access_entry.karpenter_nodes` | 讓 Karpenter Node 能加入 cluster（EC2_LINUX type） |

> **設計說明**：Karpenter Node 使用獨立的 `karpenter_node` role，和 Managed Node Group 的 `node` role 分開，避免 EKS Access Entry 衝突。

---

## 安裝步驟

### Step 1: Terraform Apply

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

### Step 2: 確認輸出值

```bash
terraform output karpenter_role_arn
# "arn:aws:iam::661515655645:role/infra-lab-dev-karpenter-role"

terraform output karpenter_node_role_name
# "infra-lab-dev-karpenter-node-role"

terraform output karpenter_interruption_queue_name
# "infra-lab-dev-karpenter-interruption"
```

### Step 3: 更新 k8s/karpenter YAML

把 `ec2nodeclass.yaml` 的佔位符換成實際值：

```yaml
role: "infra-lab-dev-karpenter-node-role"       # ← karpenter_node_role_name

subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: "infra-lab-dev-eks"   # ← cluster name

securityGroupSelectorTerms:
  - tags:
      kubernetes.io/cluster/infra-lab-dev-eks: owned  # ← cluster name
```

### Step 4: 安裝 Karpenter Helm Chart

> ⚠️ Karpenter v1.x 改用 OCI registry（`public.ecr.aws`），不再用 `charts.karpenter.sh`

```bash
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --namespace karpenter --create-namespace \
  --version 1.3.3 \
  --set "settings.clusterName=infra-lab-dev-eks" \
  --set "settings.interruptionQueue=infra-lab-dev-karpenter-interruption" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::661515655645:role/infra-lab-dev-karpenter-role" \
  --set "controller.resources.requests.cpu=250m" \
  --set "controller.resources.requests.memory=256Mi" \
  --wait --timeout 5m
```

或直接複製 Terraform output：

```bash
terraform output -raw karpenter_helm_command
```

### Step 5: 套用 EC2NodeClass + NodePool

```bash
kubectl apply -f k8s/karpenter/ec2nodeclass.yaml
kubectl apply -f k8s/karpenter/nodepool.yaml

# 確認就緒
kubectl get ec2nodeclass default   # READY=True
kubectl get nodepool default       # READY=True
```

---

## 驗證（實測結果）

### 測試 1：自動擴容

```bash
# 部署 inflate，設高 resource request 撐爆現有節點容量
kubectl create deployment inflate \
  --image=public.ecr.aws/eks-distro/kubernetes/pause:3.7 \
  --replicas=5
kubectl set resources deployment inflate --requests=cpu=1,memory=1.5Gi

# 觀察
kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type -w
kubectl get nodeclaim
```

**實測結果**：

```
# Karpenter log
computed new nodeclaim(s) to fit pod(s)  nodeclaims=1  pods=3
created nodeclaim  instance-types="c1.xlarge, c3.xlarge, c4.xlarge, c5.xlarge... and 48 other(s)"
  requests: cpu=3150m  memory=4608Mi  pods=6

# 約 60 秒後
NAME            TYPE        CAPACITY   ZONE         NODE                         READY
default-frwzk   t3.xlarge   spot       us-east-1b   ip-10-0-12-40.ec2.internal   True

# Nodes
ip-10-0-12-40.ec2.internal   Ready   NODEPOOL=default  CAPACITY-TYPE=spot  ← 新增
```

### 測試 2：自動縮容（Consolidation）

```bash
# 刪掉 inflate
kubectl delete deployment inflate

# 觀察（約 30 秒後，consolidateAfter 設定值）
kubectl get nodes -w
kubectl get nodeclaim
```

**實測結果（disruption log）**：

```
13:34:33  disrupting node(s)
          reason=empty  decision=delete
          node: ip-10-0-12-40 (t3.xlarge spot)
          → Node 空了，不需要替換，直接刪除

13:34:34  tainted node
          taint: karpenter.sh/disrupted=NoSchedule
          → 先打 taint，禁止新 Pod 排到這個 Node

13:35:06  deleted node
          → drain 完成，Node 從 cluster 移除

13:35:07  deleted nodeclaim
          → EC2 instance 終止，NodeClaim 清除
```

---

## IAM Policy 重點說明

Karpenter 的 IAM Policy 有個容易踩的坑：**`aws:RequestTag` vs `aws:ResourceTag`**。

| 情境 | 正確的 Condition key | 說明 |
|------|---------------------|------|
| `CreateLaunchTemplate`（新建） | `aws:RequestTag` | 建立時設的 tag |
| `RunInstances` 使用 launch-template（既有） | `aws:ResourceTag` | 已存在資源的 tag |
| `RunInstances` 建立 instance/volume（新建） | `aws:RequestTag` | 建立時設的 tag |
| `CreateTags` 對新建資源打 tag | `aws:RequestTag` | 和 RunInstances 同一次呼叫 |
| `CreateTags` 對已存在 instance 打 tag | `aws:ResourceTag` | instance 已有 cluster tag |

Karpenter v1.x 需要三個獨立的 EC2 write statements：

```
AllowCreateLaunchTemplate          → CreateLaunchTemplate on launch-template/* (RequestTag)
AllowScopedEC2LaunchTemplateAccess → RunInstances/CreateFleet on launch-template/* (ResourceTag)
AllowScopedEC2InstanceActionsWithTags → RunInstances/CreateFleet on instance/fleet/volume/* (RequestTag)
```

---

## 與 Managed Node Group 並存

本 Lab 採用**並存策略**：MNG 負責系統元件，Karpenter 負責工作負載。

若想完全取代 MNG：

```bash
# Phase 1：為 MNG 加 taint，讓新 workload 不落到 MNG
kubectl taint nodes -l eks.amazonaws.com/nodegroup=infra-lab-dev-nodes \
  dedicated=system:NoSchedule

# Phase 2：縮減 MNG 到 1 個 node（terraform.tfvars）
# node_desired_size = 1
# node_min_size     = 1

# Phase 3（選擇性）：移除 MNG
# 刪除 main.tf 中的 aws_eks_node_group.main
```

---

## 費用估算

| 資源 | 費用 |
|------|------|
| SQS Queue | < $0.001/月（幾乎免費） |
| EventBridge Rules | $0（前 1M events 免費） |
| Karpenter Controller Pod | 共用現有 Node，無額外費用 |
| Karpenter 啟動的 EC2 | 按需計費，依 NodePool limits 決定上限 |

> ⚠️ Lab 結束後確認 `kubectl get nodeclaim` 無殘留，或直接 `terraform destroy`。

---

## 卡關提示

| 症狀 | 原因 | 解法 |
|------|------|------|
| Karpenter Pod CrashLoopBackOff | IRSA role ARN 填錯，或 OIDC 條件錯（namespace/SA name） | 確認 `system:serviceaccount:karpenter:karpenter` |
| EC2NodeClass `InstanceProfileReady=Unknown` | IAM policy resource 寫 `KarpenterNodeInstanceProfile-*`（v0.x 舊命名） | 改成 `arn:aws:iam::*:instance-profile/*` |
| NodeClaim 啟動失敗：`ec2:RunInstances` denied on launch-template | launch-template 用了 `aws:RequestTag` 但應用 `aws:ResourceTag` | 拆成兩個 statement（見 karpenter.tf） |
| NodeClaim 啟動後 `ec2:CreateTags` denied on instance | 缺少對既有資源打 tag 的權限 | 加 `AllowTaggingKarpenterOwnedResources` statement（ResourceTag） |
| EC2NodeClass `ValidationSucceeded=False: CreateLaunchTemplateAuthCheckFailed` | `CreateLaunchTemplate` 的 resource 不含 `launch-template/*` | 加 `AllowCreateLaunchTemplate` statement |
| NodePool not ready，ignoring nodepool | Controller 剛重啟，等 20-30 秒重新 reconcile | `kubectl get ec2nodeclass` 確認 Ready=True |
| 縮容後 Node 沒消失 | `consolidateAfter` 時間還沒到，或有 PDB 阻擋 | 等 30s，或檢查 `kubectl get pdb -A` |

---

## 延伸學習

- [Karpenter 官方文件](https://karpenter.sh/docs/)
- [EC2NodeClass API Reference](https://karpenter.sh/docs/concepts/nodeclasses/)
- [NodePool API Reference](https://karpenter.sh/docs/concepts/nodepools/)
- [Karpenter vs Cluster Autoscaler](https://karpenter.sh/docs/concepts/#karpenter-vs-cluster-autoscaler)
- [Spot Instance Interruption Handling](https://karpenter.sh/docs/concepts/disruption/#interruption)
