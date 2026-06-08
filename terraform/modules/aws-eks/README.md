# AWS EKS Template

可重用的 EKS 模板，建立最小可用的 **EKS Cluster**，並可透過 `compute_mode` 選擇：

- `ec2`: EKS Managed Node Group（預設）
- `fargate`: EKS Fargate Profile

此模組刻意要求傳入既有 VPC / Subnet，避免自動建立 NAT Gateway，方便在學習情境中控制成本。

## 文件導覽

- [架構圖與部署流程（Mermaid）](./docs/architecture.md)

## 費用警告

- **EKS Control Plane**: 約 `$0.10/hr`
- **EC2 Worker Nodes**: `compute_mode = "ec2"` 時，預設 `t3.medium x 2`，約 `$0.08~0.10/hr`（依區域浮動）
- **EBS Volume**: `compute_mode = "ec2"` 時，預設每台節點 `20 GiB`
- **Fargate Pods**: `compute_mode = "fargate"` 時，依 Pod vCPU / memory 實際使用量計費，不另外建立 EC2 worker nodes
- **NAT Gateway**: 本模板不建立，但若你的 private subnet 需要對外連線，外部 VPC 可能仍會產生 NAT Gateway 費用

> 練習完成請立刻執行 `terraform destroy`，避免 EKS 控制平面、EC2 節點或 Fargate Pod 持續計費。

## 建立資源

- EKS Cluster
- EKS Cluster IAM Role
- EKS 自動建立與管理的 primary cluster Security Group
- 舊版模組曾建立的額外 cluster Security Group（保留於 state 中作為遷移用，不再綁定到 EKS cluster）
- `compute_mode = "ec2"` 時：EKS Managed Node Group、EKS Node IAM Role、必要 node policy attachments
- `compute_mode = "fargate"` 時：EKS Fargate Profile、Fargate Pod Execution Role、必要 Fargate policy attachment

## 使用方式

```bash
# 複製範例變數檔案
cp terraform.tfvars.example terraform.tfvars

# 修改 vpc_id、subnet_ids 與 endpoint / public_access_cidrs

# 初始化
terraform init

# 格式化
terraform fmt

# 驗證
terraform validate

# 規劃
terraform plan

# 部署
terraform apply

# 設定 kubectl
aws eks update-kubeconfig --region us-east-1 --name eks-template-dev-eks

# 銷毀
terraform destroy
```

## 作為 module 使用：EC2 Managed Node Group

```hcl
module "eks" {
  source = "../../modules/aws-eks"

  region      = "us-east-1"
  project     = "myapp"
  environment = "dev"

  vpc_id = module.vpc.vpc_id
  subnet_ids = [
    module.vpc.public_subnet_a_id,
    module.vpc.public_subnet_b_id,
  ]

  endpoint_public_access  = true
  endpoint_private_access = true
  public_access_cidrs     = ["0.0.0.0/0"]

  compute_mode = "ec2"

  # 若 cluster subnets 需要同時包含 private subnets，可用 node_subnet_ids 明確指定 EC2 nodes 使用 public subnets。
  node_subnet_ids = [
    module.vpc.public_subnet_a_id,
    module.vpc.public_subnet_b_id,
  ]

  node_instance_types = ["t3.medium"]
  node_desired_size   = 2
  node_min_size       = 1
  node_max_size       = 3
}
```

## 作為 module 使用：EKS Fargate Profile

```hcl
module "eks" {
  source = "../../modules/aws-eks"

  region      = "us-east-1"
  project     = "myapp"
  environment = "dev"

  vpc_id = module.vpc.vpc_id
  subnet_ids = [
    module.vpc.private_subnet_a_id,
    module.vpc.private_subnet_b_id,
  ]

  endpoint_public_access  = true
  endpoint_private_access = true
  public_access_cidrs     = ["0.0.0.0/0"]

  compute_mode = "fargate"

  fargate_selectors = [
    {
      namespace = "default"
      labels    = {}
    },
    {
      namespace = "kube-system"
      labels = {
        k8s-app = "kube-dns"
      }
    }
  ]
}
```

## 輸入變數

| 名稱 | 類型 | 預設值 | 說明 |
|------|------|--------|------|
| `region` | `string` | `us-east-1` | AWS region |
| `project` | `string` | `eks-template` | 專案名稱，用於資源命名 |
| `environment` | `string` | `dev` | 環境名稱 |
| `kubernetes_version` | `string` | `1.31` | EKS Kubernetes 版本 |
| `vpc_id` | `string` | 無 | EKS 使用的 VPC ID |
| `subnet_ids` | `list(string)` | 無 | 至少兩個不同 AZ 的 subnet IDs |
| `endpoint_public_access` | `bool` | `true` | 是否開啟公開 Kubernetes API endpoint |
| `endpoint_private_access` | `bool` | `true` | 是否開啟私有 Kubernetes API endpoint |
| `public_access_cidrs` | `list(string)` | `["0.0.0.0/0"]` | 允許連線到公開 API endpoint 的 CIDR |
| `compute_mode` | `string` | `ec2` | `ec2` 或 `fargate` |
| `node_subnet_ids` | `list(string)` | `[]` | EC2 Managed Node Group 使用的 subnet IDs；空值時沿用 `subnet_ids` |
| `node_instance_types` | `list(string)` | `["t3.medium"]` | Worker node instance types |
| `node_desired_size` | `number` | `2` | Worker node desired size |
| `node_min_size` | `number` | `1` | Worker node minimum size |
| `node_max_size` | `number` | `3` | Worker node maximum size |
| `node_disk_size` | `number` | `20` | Worker node EBS disk size GiB |
| `node_capacity_type` | `string` | `ON_DEMAND` | `ON_DEMAND` 或 `SPOT` |
| `fargate_profile_name` | `string` | `default` | Fargate Profile 名稱後綴 |
| `fargate_subnet_ids` | `list(string)` | `[]` | Fargate pods 使用的 subnet IDs；空值時沿用 `subnet_ids` |
| `fargate_selectors` | `list(object)` | `default` 與 `kube-system/kube-dns` | Fargate Profile 匹配的 namespace / labels |
| `tags` | `map(string)` | `{}` | 額外 tags |

## 輸出值

| 名稱 | 說明 |
|------|------|
| `cluster_name` | EKS cluster name |
| `cluster_arn` | EKS cluster ARN |
| `cluster_endpoint` | EKS cluster API server endpoint |
| `cluster_version` | Kubernetes version |
| `cluster_security_group_id` | EKS 自動建立並管理的 primary cluster Security Group ID |
| `cluster_role_arn` | EKS control plane IAM role ARN |
| `compute_mode` | 啟用的 compute mode |
| `node_group_name` | EKS Managed Node Group name；Fargate 模式為 `null` |
| `node_role_arn` | Worker node IAM role ARN；Fargate 模式為 `null` |
| `node_subnet_ids` | EKS Managed Node Group 實際使用的 subnet IDs；Fargate 模式為 `null` |
| `fargate_profile_name` | EKS Fargate Profile name；EC2 模式為 `null` |
| `fargate_pod_execution_role_arn` | Fargate Pod Execution Role ARN；EC2 模式為 `null` |
| `kubeconfig_command` | 設定 `kubectl` 的 AWS CLI 指令 |

## 注意事項

1. `subnet_ids` 必須至少包含兩個不同 Availability Zone 的 subnet。
2. `compute_mode = "ec2"` 會建立 EC2 Managed Node Group；`compute_mode = "fargate"` 不會建立 EC2 worker nodes。
3. 本模組不再額外綁定自建 cluster Security Group，改由 EKS 使用預設 primary cluster Security Group，降低 Managed Node Group 無法加入叢集的機率。
4. `compute_mode = "ec2"` 且 VPC 沒有 NAT Gateway 時，練習環境建議用 `node_subnet_ids` 明確指定 public subnets，並確認 subnet 會自動配置 public IP。
5. Fargate Profile 建議使用 private subnets；若使用 private subnet，請確認 pods 可以連到 EKS API、ECR 與必要 AWS APIs，通常需要 NAT Gateway 或 VPC Endpoints。
6. 若 `endpoint_private_access = false`，請不要只將 `public_access_cidrs` 設為家用 IP，否則 EC2 worker nodes 可能無法連到 public EKS API endpoint 而加入失敗。
7. 預設 `endpoint_public_access = true`、`endpoint_private_access = true`、`public_access_cidrs = ["0.0.0.0/0"]` 是為了降低學習環境踩雷機率；正式環境應改成 private endpoint、NAT/VPC Endpoints、logging、encryption、addons、IRSA 與更嚴格的 Security Group 設計。
8. 若你曾套用舊版模組，state 內可能已有 `aws_security_group.cluster`。新版會先保留這個 SG 但不再綁定到 EKS cluster，避免 AWS 尚未釋放 ENI 依賴時出現 `DependencyViolation`。

## Troubleshooting：NodeCreationFailure

若 `aws_eks_node_group` 出現：

```text
NodeCreationFailure: Instances failed to join the kubernetes cluster
```

請優先檢查：

1. EC2 worker node 是否有出網能力：public subnet 需有 public IP 與 `0.0.0.0/0 -> Internet Gateway`；private subnet 則需 NAT Gateway 或必要 VPC Endpoints。
2. `endpoint_public_access` / `endpoint_private_access` / `public_access_cidrs` 是否讓 worker node 能連到 EKS API endpoint。
3. `node_subnet_ids` 是否真的指向 public subnets；若留空則會沿用 `subnet_ids`，可能不小心把 EC2 nodes 放進沒有 NAT Gateway 的 private subnets。
4. Node IAM Role 是否已綁定 `AmazonEKSWorkerNodePolicy`、`AmazonEKS_CNI_Policy`、`AmazonEC2ContainerRegistryReadOnly`。
5. 若曾使用舊版模組建立額外 cluster Security Group，新版會先保留該 SG 並從 EKS cluster 的 `security_group_ids` 移除綁定。請先讓 `terraform apply` 完成 cluster 更新；確認 EKS / ENI 不再依賴該 SG 後，再手動規劃後續清理。

## Troubleshooting：刪除 Security Group 時發生 DependencyViolation

若 `terraform apply` 或 `terraform destroy` 出現：

```text
Error: deleting Security Group (...): DependencyViolation: resource ... has a dependent object
```

代表 AWS 端仍有資源正在使用該 Security Group，常見依賴包含 EKS control plane 建立的 ENI、Managed Node Group、EC2 network interface，或其他 Security Group rule reference。

處理順序建議：

1. 先套用新版模組，讓 EKS cluster 從舊的額外 Security Group 遷移回 EKS primary cluster Security Group。
2. 等待 AWS 釋放相關 ENI 依賴後，再檢查該 SG 是否仍被 network interface 使用。
3. 若要銷毀整個環境，先確保 Node Group / Fargate Profile 已刪除，再刪除 EKS Cluster，最後才清理 Security Group。
4. 本模組目前對舊版 `aws_security_group.cluster` 加上 `prevent_destroy = true`，避免 Terraform 在 AWS 尚未釋放依賴時強制刪除而中斷 apply。
