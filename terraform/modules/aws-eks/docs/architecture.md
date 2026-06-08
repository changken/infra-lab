# AWS EKS Template 架構圖

本文件使用 Mermaid 補充 `terraform/modules/aws-eks` 的架構與部署流程，協助快速理解 `compute_mode = "ec2"` 與 `compute_mode = "fargate"` 的差異。

> ⚠️ 費用提醒：EKS Control Plane 會持續計費；EC2 模式會另外產生 Worker Nodes / EBS 費用，Fargate 模式則依 Pod vCPU / memory 使用量計費。練習完成請立即執行 `terraform destroy`。

## 模組整體架構

```mermaid
flowchart TB
    user[使用者 / Terraform Root Module] --> eks_module[terraform/modules/aws-eks]

    eks_module --> cluster_role[EKS Cluster IAM Role]
    eks_module --> cluster_sg[EKS Cluster Additional Security Group]
    eks_module --> eks_cluster[EKS Cluster / Control Plane]

    vpc[既有 VPC] --> eks_cluster
    subnets[既有 Subnets / 至少兩個 AZ] --> eks_cluster
    cluster_role --> eks_cluster
    cluster_sg --> eks_cluster

    eks_cluster --> mode{compute_mode}
    mode -->|ec2| node_group[EKS Managed Node Group]
    mode -->|fargate| fargate_profile[EKS Fargate Profile]

    node_role[Node IAM Role] --> node_group
    node_policies[Node AWS Managed Policies] --> node_role
    node_group --> ec2_nodes[EC2 Worker Nodes]
    ec2_nodes --> pods_ec2[Kubernetes Pods]

    fargate_role[Fargate Pod Execution Role] --> fargate_profile
    fargate_policy[AmazonEKSFargatePodExecutionRolePolicy] --> fargate_role
    fargate_profile --> pods_fargate[Fargate Pods]
```

## EC2 Managed Node Group 模式

`compute_mode = "ec2"` 是預設模式，會建立 EKS Managed Node Group，Pod 會排程到 EC2 Worker Nodes 上。

```mermaid
flowchart LR
    cluster[EKS Control Plane] --> node_group[EKS Managed Node Group]
    node_group --> asg[AWS Managed Auto Scaling Group]
    asg --> node1[EC2 Worker Node]
    asg --> node2[EC2 Worker Node]

    node1 --> pod_a[Pod]
    node1 --> pod_b[Pod]
    node2 --> pod_c[Pod]

    node_role[Node IAM Role<br/>trust: ec2.amazonaws.com] --> node1
    node_role --> node2
```

### EC2 模式重點

- 會建立 `aws_eks_node_group.main`。
- 會建立 `aws_iam_role.node`，trust principal 是 `ec2.amazonaws.com`。
- 會綁定 `AmazonEKSWorkerNodePolicy`、`AmazonEKS_CNI_Policy`、`AmazonEC2ContainerRegistryReadOnly`。
- 適合學習 Worker Node、Node Group scaling、DaemonSet 與節點層級觀察。
- 成本包含 EKS Control Plane、EC2 instance 與 EBS volume。

## EKS Fargate Profile 模式

`compute_mode = "fargate"` 會建立 Fargate Profile，不會建立 EC2 Worker Nodes。符合 selector 的 Pod 會由 AWS Fargate 執行。

```mermaid
flowchart LR
    cluster[EKS Control Plane] --> profile[EKS Fargate Profile]
    selectors[Fargate Selectors<br/>namespace + labels] --> profile
    profile --> pod_default[Pod in default namespace]
    profile --> pod_dns[coredns / kube-dns Pod]

    fargate_role[Fargate Pod Execution Role<br/>trust: eks-fargate-pods.amazonaws.com] --> profile
    subnet_private[建議使用 Private Subnets] --> profile
```

### Fargate 模式重點

- 會建立 `aws_eks_fargate_profile.main`。
- 會建立 `aws_iam_role.fargate_pod_execution`，trust principal 是 `eks-fargate-pods.amazonaws.com`。
- 會綁定 `AmazonEKSFargatePodExecutionRolePolicy`。
- 不會建立 EC2 Worker Nodes，也不會建立 Node Group IAM Role。
- 適合學習 Serverless Kubernetes、namespace / label selector 與 Pod 層級計費。
- 若使用 private subnet，需確認 Pod 可連到 EKS API、ECR 與必要 AWS APIs，通常需要 NAT Gateway 或 VPC Endpoints。

## 部署流程

```mermaid
sequenceDiagram
    autonumber
    participant User as 使用者
    participant TF as Terraform
    participant IAM as AWS IAM
    participant EKS as Amazon EKS
    participant Compute as EC2 Node Group / Fargate

    User->>TF: terraform init / plan / apply
    TF->>IAM: 建立 Cluster IAM Role
    TF->>EKS: 建立 EKS Cluster
    EKS-->>TF: 回傳 Cluster endpoint / ARN

    alt compute_mode = ec2
        TF->>IAM: 建立 Node IAM Role 與 policy attachments
        TF->>Compute: 建立 Managed Node Group
        Compute-->>EKS: EC2 Nodes 加入 Cluster
    else compute_mode = fargate
        TF->>IAM: 建立 Fargate Pod Execution Role 與 policy attachment
        TF->>Compute: 建立 Fargate Profile
        Compute-->>EKS: 符合 selector 的 Pods 使用 Fargate 執行
    end

    User->>EKS: aws eks update-kubeconfig
    User->>EKS: kubectl get nodes / pods
```

## 資源建立條件

```mermaid
flowchart TD
    input[compute_mode] --> ec2_check{是否為 ec2?}
    input --> fargate_check{是否為 fargate?}

    ec2_check -->|Yes| create_node_role[建立 Node IAM Role]
    ec2_check -->|Yes| create_node_group[建立 Managed Node Group]
    ec2_check -->|No| skip_node[Node 相關資源 count = 0]

    fargate_check -->|Yes| create_fargate_role[建立 Fargate Pod Execution Role]
    fargate_check -->|Yes| create_fargate_profile[建立 Fargate Profile]
    fargate_check -->|No| skip_fargate[Fargate 相關資源 count = 0]
```

## EC2 與 Fargate 差異速查

| 項目 | `compute_mode = "ec2"` | `compute_mode = "fargate"` |
|------|--------------------------|-------------------------------|
| Compute 型態 | EC2 Worker Nodes | AWS Fargate Pods |
| Terraform 主要資源 | `aws_eks_node_group` | `aws_eks_fargate_profile` |
| IAM Role principal | `ec2.amazonaws.com` | `eks-fargate-pods.amazonaws.com` |
| 是否管理節點 | 需要理解 Node Group / EC2 | 不需要管理 EC2 節點 |
| 成本來源 | EKS Control Plane + EC2 + EBS | EKS Control Plane + Fargate Pod 用量 |
| 適合學習 | Kubernetes 節點、scaling、DaemonSet | Serverless Pod、selector、Pod 計費 |

## 建議閱讀順序

1. 先閱讀 [`README.md`](../README.md) 了解輸入變數與基本使用方式。
2. 再閱讀本文件的「模組整體架構」。
3. 依你要練習的模式閱讀「EC2 Managed Node Group 模式」或「EKS Fargate Profile 模式」。
4. 執行 `terraform plan` 前，確認 `public_access_cidrs` 已限制為自己的固定 IP。