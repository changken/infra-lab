# ECS Fargate vs EKS 對比筆記

## 核心差異一覽

| 概念 | EKS | ECS Fargate |
|------|-----|-------------|
| 運算單元 | Pod | Task |
| 部署描述 | Deployment YAML | Task Definition (JSON) |
| 服務 | Service + ClusterIP | ECS Service + ALB TG |
| 節點 | EC2 Node Group / Karpenter | 無（Fargate 管理） |
| 水平擴縮 | HPA + Karpenter | Application Auto Scaling |
| 密鑰管理 | ESO → K8s Secret → envFrom | Task Def secrets block（直接） |
| 日誌 | Fluent Bit DaemonSet | awslogs driver（原生） |
| 進入容器 | `kubectl exec` | `aws ecs execute-command` |
| 查看日誌 | `kubectl logs` | `aws logs tail` |
| 網路模式 | VPC CNI（Pod 有 VPC IP）| awsvpc（Task 有獨立 ENI）|
| 服務帳號 | IRSA（K8s SA → IAM Role）| Task Role（直接綁 Task）|
| CI/CD | GitOps (ArgoCD) | GitHub Actions → ECS deploy |
| Blue/Green 部署 | Argo Rollouts（CRD）| CodeDeploy（AWS 托管）|
| 費用複雜度 | 高（Control Plane + Nodes + NAT）| 低（Task CPU/Memory 按需計費）|

## 網路架構比較

### EKS
```
Internet → ALB（AWS LBC 建立）→ K8s Service（ClusterIP）→ Pod IP（VPC CNI）
                                     └── kube-proxy 路由
Node EC2（private subnet）← NAT Gateway ← ECR pull
```

### ECS Fargate（此 Lab）
```
Internet → ALB → Target Group（ip 模式）→ Task ENI IP（awsvpc）
                                              └── assign_public_ip = ENABLED
Task 直接出外網 → ECR pull、Secrets Manager、CloudWatch
（無 NAT Gateway，省 $32/月）
```

## 密鑰注入比較

### EKS（ESO 方案，4 個元件）
```yaml
# 1. ClusterSecretStore（連線到 AWS）
# 2. ExternalSecret（宣告要同步哪個 secret）
# 3. K8s Secret（ESO 自動建立）
# 4. Pod envFrom: secretRef
```

### ECS Fargate（原生，0 個額外元件）
```json
{
  "secrets": [{
    "name": "API_KEY",
    "valueFrom": "arn:aws:secretsmanager:...:secret/app-config:API_KEY::"
  }]
}
```
ECS Agent 在 task 啟動時直接讀取 Secrets Manager，注入為環境變數。

## 彈性伸縮比較

### EKS（兩層 scaling）
```
Pod 不足 → HPA 增加 replica
           → Karpenter 發現 Pending Pod → 開新 Node
Pod 多餘 → HPA 縮減 replica
           → Karpenter 縮減 Node（bin packing）
```

### ECS Fargate（一層 scaling）
```
Task CPU/Memory 超標 → Application Auto Scaling 增加 desired_count
                      → Fargate 自動分配算力，無需等 Node
Task 利用率下降 → Application Auto Scaling 縮減 desired_count
```

## 何時選 ECS Fargate vs EKS

### 選 ECS Fargate 當：
- 容器化應用，不需要 Kubernetes 生態系（Helm, CRDs, operators）
- 團隊規模小，不想維運 Kubernetes control plane
- 快速上線，需要最少 DevOps 投入
- 費用敏感，想按實際 Task 算力計費（不付閒置 Node 費用）
- 已在 AWS，想要深度整合（IAM, ALB, CloudWatch）

### 選 EKS 當：
- 需要複雜的 workload 排程（affinity, taint, priority）
- 使用大量 K8s 生態系工具（Istio, ArgoCD, Prometheus Operator）
- 跨雲可移植性需求
- GPU workloads、機器學習
- 大型工程組織，有專職 Platform Team 維運 K8s

## 費用對比（本 Lab 規模）

| 費用項目 | EKS Lab | ECS Fargate Lab |
|---------|---------|-----------------|
| Control Plane | $0.10/hr | 無 |
| Node/EC2 | ~$0.028/hr（2× SPOT t3.medium）| 無 |
| NAT Gateway | $0.045/hr | **$0** |
| ALB | $0.008/hr | $0.008/hr |
| Fargate Task | 無 | ~$0.024/hr（2 tasks） |
| **總計** | **~$0.181/hr** | **~$0.032/hr** |

> ECS Fargate 約便宜 **82%**（主要省在 NAT Gateway + 無固定 Node）
> 隨 Task 數量增加差距會縮小，大規模時 EKS SPOT 可能更划算
