# Multi-Cloud K3s 開發環境建置指南

本文件記錄專案的詳細建置過程，包含 Azure 和 AWS 的手動 CLI 方式與 Terraform 資源匯入，作為歷史參考。

> [!NOTE]
> 日常操作請參閱 [README.md](../README.md)

---

## 0. 事前準備（apply 前必做）

### 0.1 產生 SSH 緊急存取金鑰

```bash
mkdir -p ./.ssh

# Azure 用
ssh-keygen -t ed25519 -f ./.ssh/azure_emergency_ed25519 -N ""

# AWS 用
ssh-keygen -t ed25519 -f ./.ssh/aws_emergency_ed25519 -N ""
```

### 0.2 建立 SSM SecureString 參數

Terraform apply **之前**，需先在 SSM 手動建立 Tailscale auth key。
K3s node-token 由 CP cloud-init 自動寫入，不需手動建立。

```bash
AWS_REGION="us-east-1"

# Tailscale Auth Key（從 https://login.tailscale.com/admin/settings/keys 取得）
aws ssm put-parameter \
  --name "/k3s-lab/tailscale-auth-key" \
  --value "tskey-auth-REPLACE_ME" \
  --type SecureString \
  --region "$AWS_REGION"

# 確認已建立
aws ssm get-parameter \
  --name "/k3s-lab/tailscale-auth-key" \
  --with-decryption \
  --region "$AWS_REGION"
```

### 0.3 destroy 後清理 SSM

`terraform destroy` 不會自動刪除 SSM parameters（避免意外資料遺失）。
需手動清理：

```bash
aws ssm delete-parameter --name "/k3s-lab/tailscale-auth-key" --region us-east-1
aws ssm delete-parameter --name "/k3s-lab/node-token" --region us-east-1
```

---

## 1. 手動建立環境（CLI 方式）

> 此章節為歷史記錄，說明專案最初如何以 CLI 建立。
> 現在建議直接使用 `terraform apply`。

### 1.1 Azure 資源建立

#### 建立 Azure 資源

```bash
# 建立 Resource Group
az group create --name my-k3s-lab-rg --location japaneast

# 建立 VM
az vm create \
  --resource-group my-k3s-lab-rg \
  --name my-k3s-vm \
  --image Ubuntu2404 \
  --size Standard_B2s \
  --admin-username ubuntu \
  --ssh-key-values ./.ssh/azure_emergency_ed25519.pub \
  --public-ip-sku Standard
```

#### 安裝 Tailscale 與 K3s (Azure)

```bash
# 透過 Tailscale SSH 進入 VM 後執行
TS_IP=$(tailscale ip -4)
curl -sfL https://get.k3s.io | sh -s - server --tls-san $TS_IP --node-external-ip $TS_IP
```

### 1.2 AWS 資源建立（3 節點叢集）

#### 建立基礎網路資源

```bash
AWS_REGION="us-east-1"
KEY_NAME="my-k3s-lab-emergency-key"

# 匯入 SSH public key
aws ec2 import-key-pair \
  --key-name "$KEY_NAME" \
  --public-key-material fileb://./.ssh/aws_emergency_ed25519.pub \
  --region "$AWS_REGION"

# 建立 VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.1.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=my-k3s-lab-vpc}]' \
  --region "$AWS_REGION" \
  --query 'Vpc.VpcId' --output text)

# 建立 Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=my-k3s-lab-igw}]' \
  --region "$AWS_REGION" \
  --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway \
  --vpc-id "$VPC_ID" \
  --internet-gateway-id "$IGW_ID" \
  --region "$AWS_REGION"

# 建立 Subnet
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.1.1.0/24 \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=my-k3s-lab-subnet}]' \
  --region "$AWS_REGION" \
  --query 'Subnet.SubnetId' --output text)

# 建立 Route Table 並設定路由
RTB_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=my-k3s-lab-rt}]' \
  --region "$AWS_REGION" \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route \
  --route-table-id "$RTB_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID" \
  --region "$AWS_REGION"

aws ec2 associate-route-table \
  --subnet-id "$SUBNET_ID" \
  --route-table-id "$RTB_ID" \
  --region "$AWS_REGION"
```

#### 建立 Security Group（含 K3s 節點間規則）

```bash
SG_ID=$(aws ec2 create-security-group \
  --group-name my-k3s-lab-sg \
  --description "Security group for K3s nodes (Tailscale-first)" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query 'GroupId' --output text)

# Egress: 允許所有 outbound
aws ec2 authorize-security-group-egress \
  --group-id "$SG_ID" \
  --protocol all \
  --cidr 0.0.0.0/0 \
  --region "$AWS_REGION"

# K3s API (節點間 self-referencing)
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 6443 \
  --source-group "$SG_ID" \
  --region "$AWS_REGION"

# K3s API (kubectl 外部存取)
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 6443 \
  --cidr 0.0.0.0/0 \
  --region "$AWS_REGION"

# Flannel VXLAN (pod 網路 overlay，節點間)
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol udp --port 8472 \
  --source-group "$SG_ID" \
  --region "$AWS_REGION"

# Kubelet (節點間 health check)
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 10250 \
  --source-group "$SG_ID" \
  --region "$AWS_REGION"
```

#### 建立 IAM Role（SSM 存取）

```bash
# 建立 Trust Policy
cat > /tmp/k3s-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Action": "sts:AssumeRole",
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" }
  }]
}
EOF

ROLE_ARN=$(aws iam create-role \
  --role-name my-k3s-lab-node-role \
  --assume-role-policy-document file:///tmp/k3s-trust-policy.json \
  --query 'Role.Arn' --output text)

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 建立 SSM 最小權限 Policy
cat > /tmp/k3s-ssm-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["ssm:PutParameter", "ssm:GetParameter", "ssm:DeleteParameter"],
    "Resource": "arn:aws:ssm:${AWS_REGION}:${ACCOUNT_ID}:parameter/k3s-lab/*"
  }]
}
EOF

aws iam put-role-policy \
  --role-name my-k3s-lab-node-role \
  --policy-name my-k3s-lab-ssm-policy \
  --policy-document file:///tmp/k3s-ssm-policy.json

aws iam create-instance-profile \
  --instance-profile-name my-k3s-lab-node-profile

aws iam add-role-to-instance-profile \
  --instance-profile-name my-k3s-lab-node-profile \
  --role-name my-k3s-lab-node-role
```

#### 建立 Elastic IP 與 EC2 Instances

```bash
# 取得最新 Ubuntu 24.04 AMI
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
            "Name=state,Values=available" \
  --region "$AWS_REGION" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text)

# 分配 Elastic IP（Control Plane 用）
EIP_ALLOC=$(aws ec2 allocate-address \
  --domain vpc \
  --region "$AWS_REGION" \
  --query 'AllocationId' --output text)

EIP=$(aws ec2 describe-addresses \
  --allocation-ids "$EIP_ALLOC" \
  --region "$AWS_REGION" \
  --query 'Addresses[0].PublicIp' --output text)

# 建立 Control Plane（使用 user-data-cp.sh）
CP_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type t3.medium \
  --key-name "$KEY_NAME" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --associate-public-ip-address \
  --iam-instance-profile Name=my-k3s-lab-node-profile \
  --user-data file://user-data-cp.sh \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=64,VolumeType=gp3,Encrypted=true,DeleteOnTermination=true}' \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=my-k3s-cp}]' \
  --region "$AWS_REGION" \
  --query 'Instances[0].InstanceId' --output text)

# 關聯 EIP
aws ec2 associate-address \
  --instance-id "$CP_ID" \
  --allocation-id "$EIP_ALLOC" \
  --region "$AWS_REGION"

# 等待 CP 完成（cloud-init 約 3-5 分鐘）
echo "Waiting for CP cloud-init..."
aws ec2 wait instance-status-ok --instance-ids "$CP_ID" --region "$AWS_REGION"

# 取得 CP private IP
CP_PRIVATE_IP=$(aws ec2 describe-instances \
  --instance-ids "$CP_ID" \
  --region "$AWS_REGION" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

# 建立 2 台 Worker（使用 user-data-worker.sh）
for i in 0 1; do
  aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type t3.small \
    --key-name "$KEY_NAME" \
    --subnet-id "$SUBNET_ID" \
    --security-group-ids "$SG_ID" \
    --associate-public-ip-address \
    --iam-instance-profile Name=my-k3s-lab-node-profile \
    --user-data file://user-data-worker.sh \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=32,VolumeType=gp3,Encrypted=true,DeleteOnTermination=true}' \
    --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=my-k3s-worker-$i}]" \
    --region "$AWS_REGION" \
    --query 'Instances[0].InstanceId' --output text
done
```

---

## 2. Terraform 資源匯入

若要將現有資源導入 Terraform 管理：

### 2.1 Azure 資源匯入

```bash
SUB_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
RG_ID="/subscriptions/$SUB_ID/resourceGroups/my-k3s-lab-rg"

terraform init

terraform import azurerm_resource_group.rg "$RG_ID"
terraform import azurerm_virtual_network.vnet "$RG_ID/providers/Microsoft.Network/virtualNetworks/my-k3s-lab-vnet"
terraform import azurerm_subnet.subnet "$RG_ID/providers/Microsoft.Network/virtualNetworks/my-k3s-lab-vnet/subnets/my-k3s-lab-subnet"
terraform import azurerm_network_interface.nic "$RG_ID/providers/Microsoft.Network/networkInterfaces/my-k3s-lab-nic"
terraform import azurerm_linux_virtual_machine.vm "$RG_ID/providers/Microsoft.Compute/virtualMachines/my-k3s-vm"
```

### 2.2 AWS 資源匯入

```bash
export AWS_REGION="us-east-1"
terraform init

# 網路基礎
terraform import aws_vpc.main vpc-xxxxx
terraform import aws_internet_gateway.main igw-xxxxx
terraform import aws_subnet.main subnet-xxxxx
terraform import aws_route_table.main rtb-xxxxx
terraform import aws_route_table_association.main subnet-xxxxx/rtb-xxxxx
terraform import aws_security_group.k3s sg-xxxxx

# SSH Key Pair
terraform import aws_key_pair.emergency my-k3s-lab-emergency-key

# IAM（需先查詢）
terraform import aws_iam_role.k3s_node my-k3s-lab-node-role
terraform import aws_iam_role_policy.k3s_ssm my-k3s-lab-node-role:my-k3s-lab-ssm-policy
terraform import aws_iam_instance_profile.k3s_node my-k3s-lab-node-profile

# Elastic IP（需先查詢 allocation ID）
terraform import aws_eip.k3s_cp eipalloc-xxxxx

# EC2 Instances
terraform import aws_instance.k3s_cp i-xxxxx           # Control Plane
terraform import aws_instance.k3s_worker[0] i-xxxxx   # Worker 0
terraform import aws_instance.k3s_worker[1] i-xxxxx   # Worker 1

# EIP Association
terraform import aws_eip_association.k3s_cp eipassoc-xxxxx
```

**查詢資源 ID 的指令：**

```bash
# VPC
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=my-k3s-lab-vpc" \
  --query 'Vpcs[0].VpcId' --output text

# CP Instance ID
aws ec2 describe-instances --filters "Name=tag:Name,Values=my-k3s-cp" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text

# Worker Instance IDs
aws ec2 describe-instances --filters "Name=tag:Name,Values=my-k3s-worker-*" \
  --query 'Reservations[*].Instances[0].InstanceId' --output text

# EIP Allocation ID
aws ec2 describe-addresses --filters "Name=tag:Name,Values=my-k3s-lab-cp-eip" \
  --query 'Addresses[0].AllocationId' --output text
```

---

## 3. Terraform Cloud 設定

1. 前往 [Terraform Cloud](https://app.terraform.io) 註冊/登入
2. 建立 Organization 和 Workspace
3. **重要**：Workspace Settings → General → Execution Mode 選擇 `Local`
4. 執行 `terraform login` 完成認證

---

## 4. 常見問題

### 4.1 Azure 相關

| 問題 | 解法 |
|------|------|
| OS Disk 名稱不符 | 在 `main.tf` 中指定完整 disk 名稱 |
| Trusted Launch | 確保 `secure_boot_enabled = true`, `vtpm_enabled = true` |
| Image 不符 | 確認使用 `ubuntu-24_04-lts` offer |
| Azure CLI 未登入 | 執行 `az login` |

### 4.2 AWS 相關

| 問題 | 解法 |
|------|------|
| AMI ID 變動 | 使用 `data.aws_ami` 動態查詢最新 AMI |
| User data 未執行 | 檢查 `aws ec2 get-console-output --instance-id <id>` |
| EC2 無法連 Tailscale | 確認 SG outbound 允許 0.0.0.0/0 |
| AWS CLI 未配置 | 執行 `aws configure` |
| Workers 無法加入叢集 | 確認 CP 已啟動且 SSM `/k3s-lab/node-token` 已寫入 |
| SSM GetParameter 拒絕 | 確認 IAM instance profile 已掛載，policy 允許 `k3s-lab/*` |
| SSM GetParameter 找不到 | CP 的 K3s 尚未啟動，等 3-5 分鐘或查 CP console output |
| Tailscale 未出現在 Tailnet | 確認 SSM `/k3s-lab/tailscale-auth-key` 存在且未過期 |
| EIP 沒關聯到 CP | 檢查 `aws_eip_association.k3s_cp` 是否 apply 成功 |
| kubeconfig 連不上 | 確認使用 EIP (`terraform output aws_eip_public_ip`)，非動態 public IP |

### 4.3 Terraform 相關

| 問題 | 解法 |
|------|------|
| State 衝突 | 確認 Terraform Cloud workspace 設定為 Local execution |
| Provider 版本衝突 | 執行 `terraform init -upgrade` |
| 變數未定義 | 檢查 `terraform.tfvars` 是否包含所有必要變數 |
| `aws_instance.k3s` not found | 舊資源名稱，已改為 `aws_instance.k3s_cp`，需重新 import |

---

## 5. 多雲架構注意事項

### 5.1 網路架構

```
Internet
  │
  ├─ Azure (japaneast) ──────────────────────────────┐
  │    Standard_B2s (2vCPU/4GB)                      │
  │    Ubuntu 24.04 LTS                              │
  │    VNet: 10.0.0.0/16                             │
  │    K3s server (standalone)                       │
  │                                                  │
  └─ AWS us-east-1 VPC (10.1.0.0/16) ───────────────┤
       Subnet: 10.1.1.0/24                           │
       │                                             │
       ├─ k3s-cp (t3.medium, 2vCPU/4GB)             │
       │    EIP: <stable public IP>                  │
       │    K3s server                               │
       │    SSM: writes /k3s-lab/node-token          │
       │                                             │
       ├─ k3s-worker-0 (t3.small, 1vCPU/2GB)        │
       │    K3s agent (joins via CP private IP)      │
       │                                             │
       └─ k3s-worker-1 (t3.small, 1vCPU/2GB)        │
            K3s agent (joins via CP private IP)      │
                                                     │
    SSM Parameter Store                              │
    ├─ /k3s-lab/tailscale-auth-key (SecureString)   │
    └─ /k3s-lab/node-token (SecureString)           │
                                                     │
         ← Tailscale Mesh VPN ──────────────────────►│
         (Azure + AWS 3 nodes 互連)
```

**啟動順序（cloud-init 自動完成）：**

```
Terraform apply
  │
  ├─ 1. 分配 EIP → 建立 CP instance（注入 EIP）→ 關聯 EIP
  ├─ 2. 建立 2 台 worker（depends_on CP）
  │
CP cloud-init (~3-5 min):
  │  Update → K3s server → 等 token → 寫 SSM → Tailscale
  │
Worker cloud-init (concurrent):
     Update → 輪詢 SSM token（最多 10 分鐘）→ K3s agent join → Tailscale
```

### 5.2 成本優化

| 項目 | Azure | AWS CP | AWS Worker × 2 | 合計 |
|------|-------|--------|----------------|------|
| **規格** | Standard_B2s | t3.medium | t3.small × 2 | — |
| **費用/hr** | ~$0.042 | ~$0.042 | ~$0.042（合計） | ~$0.125 |
| **費用/月（24/7）** | ~$30 | ~$30 | ~$30 | **~$90** ⚠️ |

**節省費用：**

```bash
# 停止全部 AWS instances（EIP 閒置時收費 $0.005/hr）
aws ec2 stop-instances \
  --instance-ids \
    $(terraform output -raw aws_instance_id) \
    $(terraform output -json worker_instance_ids | jq -r '.[]' | tr '\n' ' ') \
  --region us-east-1

# 啟動
aws ec2 start-instances \
  --instance-ids \
    $(terraform output -raw aws_instance_id) \
    $(terraform output -json worker_instance_ids | jq -r '.[]' | tr '\n' ' ') \
  --region us-east-1

# Azure
az vm deallocate --resource-group my-k3s-lab-rg --name my-k3s-vm
az vm start --resource-group my-k3s-lab-rg --name my-k3s-vm
```

> **注意**：長期不使用建議 `terraform destroy`，並手動刪除 SSM parameters（見章節 0.3）。

### 5.3 kubeconfig 取得

```bash
# AWS 叢集（使用 EIP，stop/start 後仍有效）
EIP=$(terraform output -raw aws_eip_public_ip)
tailscale ssh ubuntu@k3s-cp "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s|https://127.0.0.1:6443|https://$EIP:6443|g" \
  > kubeconfig/k3s-aws.yaml

# Azure 叢集
tailscale ssh ubuntu@my-k3s-vm "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig/k3s-azure.yaml
AZURE_TS_IP=$(tailscale ssh ubuntu@my-k3s-vm "tailscale ip -4")
sed -i "s|https://127.0.0.1:6443|https://$AZURE_TS_IP:6443|g" kubeconfig/k3s-azure.yaml

# 確認 AWS 3 節點都 Ready
KUBECONFIG=kubeconfig/k3s-aws.yaml kubectl get nodes

# 預期輸出
# NAME           STATUS   ROLES                  AGE
# k3s-cp         Ready    control-plane,master   Xm
# k3s-worker-0   Ready    <none>                 Xm
# k3s-worker-1   Ready    <none>                 Xm
```

---

## 6. 參考資料

- [K3s 官方文件](https://docs.k3s.io/)
- [Tailscale 官方文件](https://tailscale.com/kb/)
- [AWS SSM Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Cloud-init 文件](https://cloudinit.readthedocs.io/)
