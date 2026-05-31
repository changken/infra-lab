# AWS K3s 叢集建置指南

本文件記錄 1 CP + 2 Workers 的 K3s 叢集詳細建置過程，包含手動 CLI 方式與 Terraform 資源匯入，作為歷史參考。

> [!NOTE]
> 日常操作請參閱 [README.md](../README.md)

---

## 0. 事前準備（apply 前必做）

### 0.1 產生 SSH 緊急存取金鑰

```bash
mkdir -p ./.ssh
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

### 1.1 AWS 資源建立（3 節點叢集）

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

aws iam create-role \
  --role-name my-k3s-lab-node-role \
  --assume-role-policy-document file:///tmp/k3s-trust-policy.json

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

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

# 建立 Control Plane
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
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=my-cp}]' \
  --region "$AWS_REGION" \
  --query 'Instances[0].InstanceId' --output text)

# 關聯 EIP
aws ec2 associate-address \
  --instance-id "$CP_ID" \
  --allocation-id "$EIP_ALLOC" \
  --region "$AWS_REGION"

# 取得 CP private IP（workers 需要）
CP_PRIVATE_IP=$(aws ec2 describe-instances \
  --instance-ids "$CP_ID" \
  --region "$AWS_REGION" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

echo "CP: $CP_ID, EIP: $EIP, Private IP: $CP_PRIVATE_IP"
echo "等待 CP cloud-init 完成後再建 workers..."

# 建立 2 台 Workers
for i in 1 2; do
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
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=my-worker-$i}]" \
    --region "$AWS_REGION" \
    --query 'Instances[0].InstanceId' --output text
done
```

---

## 2. Terraform 資源匯入

若要將現有資源導入 Terraform 管理：

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

# IAM
terraform import aws_iam_role.k3s_node my-k3s-lab-node-role
terraform import aws_iam_role_policy.k3s_ssm my-k3s-lab-node-role:my-k3s-lab-ssm-policy
terraform import aws_iam_instance_profile.k3s_node my-k3s-lab-node-profile

# Elastic IP
terraform import aws_eip.k3s_cp eipalloc-xxxxx

# EC2 Instances
terraform import aws_instance.k3s_cp i-xxxxx
terraform import "aws_instance.k3s_worker[0]" i-xxxxx
terraform import "aws_instance.k3s_worker[1]" i-xxxxx

# EIP Association
terraform import aws_eip_association.k3s_cp eipassoc-xxxxx
```

**查詢資源 ID：**

```bash
# VPC
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=my-k3s-lab-vpc" \
  --query 'Vpcs[0].VpcId' --output text

# CP instance
aws ec2 describe-instances --filters "Name=tag:Name,Values=my-cp" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text

# Worker instances
aws ec2 describe-instances --filters "Name=tag:Name,Values=my-worker-*" \
  --query 'Reservations[*].Instances[0].[Tags[?Key==`Name`].Value|[0],InstanceId]' \
  --output table

# EIP allocation ID
aws ec2 describe-addresses --filters "Name=tag:Name,Values=my-k3s-lab-cp-eip" \
  --query 'Addresses[0].AllocationId' --output text
```

---

## 3. Terraform 設定說明

本模組使用 **Local state**（`required_version >= 1.6.0`），不依賴 Terraform Cloud。

```bash
# 初始化（第一次或新機器）
terraform init

# state 位置
ls .terraform/terraform.tfstate
```

> 若要改用 Terraform Cloud，取消 `main.tf` 中的 `cloud {}` 註解並執行 `terraform login`。

---

## 4. 常見問題

| 症狀 | 解法 |
|------|------|
| Worker 無法加入叢集 | CP cloud-init 約需 3-5 分鐘；查 `aws ec2 get-console-output --instance-id <cp-id>` |
| SSM GetParameter 拒絕 | 確認 IAM instance profile 已掛載，policy 允許 `k3s-lab/*` |
| SSM 找不到 node-token | CP 的 K3s 尚未啟動；worker 會輪詢最多 10 分鐘 |
| Tailscale 未出現 | 確認 SSM `/k3s-lab/tailscale-auth-key` 存在且未過期；Tailscale 失敗不影響叢集運作 |
| kubeconfig 連不上 | 使用 EIP（`terraform output aws_eip_public_ip`），stop/start 後仍有效 |
| EIP 費用持續 | 停機後 EIP 閒置收 $0.005/hr；長期不用請 `terraform destroy` |
| AMI ID 變動 | `data.aws_ami` 自動抓最新，每次 plan 可能顯示 update（正常）|
| Terraform state 衝突 | 確認只有一個人/流程同時執行 apply |

---

## 5. 架構說明

### 網路架構

```
Internet
  │
  └─ AWS us-east-1 VPC (10.1.0.0/16)
       Subnet: 10.1.1.0/24
       │
       ├─ my-cp (t3.medium)
       │    EIP: <stable public IP> ← kubectl 用
       │    K3s server
       │    Writes /k3s-lab/node-token to SSM
       │
       ├─ my-worker-1 (t3.small)
       │    K3s agent (joins via CP private IP)
       │    Polls /k3s-lab/node-token from SSM
       │
       └─ my-worker-2 (t3.small)
            K3s agent

SSM Parameter Store
  ├─ /k3s-lab/tailscale-auth-key (SecureString) ← 手動建立
  └─ /k3s-lab/node-token         (SecureString) ← CP 自動寫入

本機 ←→ Tailscale VPN ←→ my-cp, my-worker-1, my-worker-2
```

### 費用

| 資源 | 規格 | 費用/hr |
|------|------|---------|
| CP (t3.medium) | 2 vCPU / 4 GB | $0.0416 |
| Worker × 2 (t3.small) | 1 vCPU / 2 GB | $0.0208 × 2 |
| EIP（開機中） | — | 免費 |
| **合計（開機中）** | | **~$0.083/hr (~$60/月)** |

### kubeconfig 取得

```bash
EIP=$(terraform output -raw aws_eip_public_ip)
tailscale ssh ubuntu@my-cp "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s|https://127.0.0.1:6443|https://$EIP:6443|g" \
  > kubeconfig/k3s-aws.yaml

KUBECONFIG=kubeconfig/k3s-aws.yaml kubectl get nodes

# 預期
# NAME         STATUS   ROLES                  AGE
# my-cp        Ready    control-plane,master   Xm
# my-worker-1  Ready    <none>                 Xm
# my-worker-2  Ready    <none>                 Xm
```

---

## 6. 參考資料

- [K3s 官方文件](https://docs.k3s.io/)
- [Tailscale 官方文件](https://tailscale.com/kb/)
- [AWS SSM Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Cloud-init 文件](https://cloudinit.readthedocs.io/)
