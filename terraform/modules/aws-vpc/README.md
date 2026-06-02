# Simple VPC Configuration for k3s

簡單的 AWS VPC 配置，包含 Public / Private Subnet、Internet Gateway、Security Groups 和 SSH Key，專為 k3s 叢集設計。

## 費用

- **VPC + IGW + Subnets**: 免費
- **NAT Gateway**: 未包含（避免 ~$32/月費用）
- **Security Groups**: 免費
- **Key Pair**: 免費

## 使用方式

```bash
# 複製範例變數檔案
cp terraform.tfvars.example terraform.tfvars

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

# 銷毀
terraform destroy
```

## 配置細節

- **VPC CIDR**: `192.168.0.0/16`
- **Public Subnet A**: `192.168.1.0/24` (AZ-a)
- **Public Subnet B**: `192.168.3.0/24` (AZ-b)
- **Private Subnet A**: `192.168.2.0/24` (AZ-a)
- **Private Subnet B**: `192.168.4.0/24` (AZ-b)

## 路由表配置

- **Public Route Table**: `0.0.0.0/0` → Internet Gateway
- **Private Route Table**: 只有 local 路由（無 NAT Gateway）

## Security Groups

### k3s-nodes-sg
專為 k3s 節點設計的 Security Group，包含：
- SSH (port 22) - 遠端存取
- k3s API (port 6443) - Kubernetes API
- k3s agent (port 10250) - 節點間通訊
- Flannel VXLAN (port 8472 UDP) - 叢集網路

### internal-sg
專為內部通訊設計的 Security Group，允許所有內部流量。

## SSH Key

- **Key Pair Name**: `k3s-key-pair`
- **Public Key Source**: `~/.ssh/id_rsa.pub`

## 特性

- Public Subnet: `map_public_ip_on_launch = true`
- VPC: `enable_dns_hostnames = true`, `enable_dns_support = true`
- 所有資源都有適當的 Name tags
- 專為 k3s 叢集優化的 Security Groups

## 輸入變數

| 名稱 | 類型 | 預設值 | 說明 |
|------|------|--------|------|
| `vpc_cidr` | `string` | `192.168.0.0/16` | VPC CIDR block |
| `public_subnet_a_cidr` | `string` | `192.168.1.0/24` | Public subnet A CIDR |
| `public_subnet_b_cidr` | `string` | `192.168.3.0/24` | Public subnet B CIDR |
| `private_subnet_a_cidr` | `string` | `192.168.2.0/24` | Private subnet A CIDR |
| `private_subnet_b_cidr` | `string` | `192.168.4.0/24` | Private subnet B CIDR |
| `availability_zone_a` | `string` | `ap-northeast-1a` | Availability zone A |
| `availability_zone_b` | `string` | `ap-northeast-1c` | Availability zone B |
| `enable_dns_hostnames` | `bool` | `true` | Enable DNS hostnames |
| `enable_dns_support` | `bool` | `true` | Enable DNS support |
| `personal_pc_cidr` | `string` | `118.150.143.171/32` | 家用電腦或特定管理的外部 IP CIDR |

## 輸出值

| 名稱 | 說明 |
|------|------|
| `vpc_id` | VPC ID |
| `vpc_cidr_block` | VPC CIDR block |
| `internet_gateway_id` | Internet Gateway ID |
| `public_subnet_a_id` | Public subnet A ID |
| `public_subnet_b_id` | Public subnet B ID |
| `private_subnet_a_id` | Private subnet A ID |
| `private_subnet_b_id` | Private subnet B ID |
| `public_route_table_id` | Public route table ID |
| `private_route_table_id` | Private route table ID |
| `k3s_security_group_id` | k3s Security Group ID |
| `internal_security_group_id` | Internal Security Group ID |
| `k3s_key_pair_name` | k3s Key Pair Name |

## 架構圖

```
Internet
   │
   ▼
Internet Gateway
   │
   ├── Public Route Table (0.0.0.0/0 → IGW)
   │     ├── public-subnet-a (192.168.1.0/24, AZ-a)
   │     │     └── k3s nodes (SG: k3s-nodes-sg, Key: k3s-key-pair)
   │     └── public-subnet-b (192.168.3.0/24, AZ-b)
   │           └── k3s nodes (SG: k3s-nodes-sg, Key: k3s-key-pair)
   │
   └── Private Route Table (local only)
         ├── private-subnet-a (192.168.2.0/24, AZ-a)
         └── private-subnet-b (192.168.4.0/24, AZ-b)
```

## 專案結構

```
terraform/modules/aws-vpc/
├── terraform.tf          # Terraform 和 Provider 配置
├── locals.tf             # 區域變數
├── variables.tf          # 輸入變數
├── main.tf               # VPC、Subnet、Route Table
├── security_groups.tf    # Security Groups
├── key_pair.tf           # SSH Key Pair
├── outputs.tf            # 輸出值
├── terraform.tfvars.example  # 範例變數檔案
└── .gitignore            # 忽略檔案
```

## 使用 k3s 叢集

部署完成後，您可以使用以下資源來建立 k3s 叢集：

```hcl
# 在您的 k3s EC2 實例配置中使用：
vpc_security_group_ids = [module.vpc.k3s_security_group_id]
key_name              = module.vpc.k3s_key_pair_name
subnet_id             = module.vpc.public_subnet_a_id
```

## 注意事項

1. 請確保您的 SSH 公鑰位於 `~/.ssh/id_rsa.pub`，或者修改 `key_pair.tf` 中的路徑。
2. Security Group 規則允許來自任何 IP 的存取，請根據您的需求調整 CIDR 塊。
3. 此配置專為 k3s 設計，但也可以用於其他用途。