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
- EKS cluster 額外 Security Group
- `compute_mode = "ec2"` 時：EKS Managed Node Group、EKS Node IAM Role、必要 node policy attachments
- `compute_mode = "fargate"` 時：EKS Fargate Profile、Fargate Pod Execution Role、必要 Fargate policy attachment

## 使用方式

```bash
# 複製範例變數檔案
cp terraform.tfvars.example terraform.tfvars

# 修改 vpc_id、subnet_ids 與 public_access_cidrs

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

  public_access_cidrs = ["203.0.113.10/32"]

  compute_mode = "ec2"

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

  public_access_cidrs = ["203.0.113.10/32"]

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
| `endpoint_private_access` | `bool` | `false` | 是否開啟私有 Kubernetes API endpoint |
| `public_access_cidrs` | `list(string)` | `["0.0.0.0/0"]` | 允許連線到公開 API endpoint 的 CIDR |
| `compute_mode` | `string` | `ec2` | `ec2` 或 `fargate` |
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
| `cluster_security_group_id` | EKS cluster 額外 Security Group ID |
| `cluster_role_arn` | EKS control plane IAM role ARN |
| `compute_mode` | 啟用的 compute mode |
| `node_group_name` | EKS Managed Node Group name；Fargate 模式為 `null` |
| `node_role_arn` | Worker node IAM role ARN；Fargate 模式為 `null` |
| `fargate_profile_name` | EKS Fargate Profile name；EC2 模式為 `null` |
| `fargate_pod_execution_role_arn` | Fargate Pod Execution Role ARN；EC2 模式為 `null` |
| `kubeconfig_command` | 設定 `kubectl` 的 AWS CLI 指令 |

## 注意事項

1. `subnet_ids` 必須至少包含兩個不同 Availability Zone 的 subnet。
2. `compute_mode = "ec2"` 會建立 EC2 Managed Node Group；`compute_mode = "fargate"` 不會建立 EC2 worker nodes。
3. Fargate Profile 建議使用 private subnets；若使用 public subnets，請確認網路路由與安全需求符合預期。
4. 若使用 private subnet，請確認節點或 Fargate pods 可以連到 EKS API、ECR 與必要 AWS APIs；通常需要 NAT Gateway 或 VPC Endpoints。
5. 練習環境建議將 `public_access_cidrs` 限制為自己的固定 IP，例如 `203.0.113.10/32`。
6. 預設為簡化學習用途；正式環境應補強 logging、encryption、addons、IRSA 與細緻化 Security Group 規則。
