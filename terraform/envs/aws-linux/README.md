# aws-linux — Amazon Linux 2023 開發 / 跳板機

🟢 **費用等級：安全** — t3.micro Spot ~$0.003/hr（約 $2/月）

長駐環境：Amazon Linux 2023 EC2，作為 SSH 跳板機與開發環境。
可延伸連接私有子網路中的 RDS、Aurora、EKS 等資源。

## 架構

```
你的電腦
    │
    │ SSH :22
    ▼
┌─────────────────────────────────┐
│  Public Subnet (10.20.1.0/24)  │
│  AL2023 Spot t3.micro           │
│  - SSM Session Manager          │
│  - CloudWatch Agent             │
│  - git, curl, jq, aws cli      │
└─────────────────────────────────┘
    │
    │ (可延伸)
    ▼
┌─────────────────────────────────┐
│  Private Subnet                 │
│  RDS / Aurora / EKS nodes       │
└─────────────────────────────────┘
```

## 快速開始

```bash
# 1. 設定變數
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入 my_ip（curl ifconfig.me）

# 2. 初始化與部署
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

## 連線方式

### SSH（需要 Key Pair）
```bash
# apply 後執行，取得 ssh 指令
terraform output ssh_command

# 或直接：
ssh -i ../../modules/aws-linux/linux-bastion-key.pem ec2-user@<public_ip>
```

### SSM Session Manager（免 Key Pair，推薦）
```bash
terraform output linux_instance_id
aws ssm start-session --target <instance_id>
```

## 驗證

```bash
# 確認 instance 狀態
aws ec2 describe-instances \
  --instance-ids $(terraform output -raw linux_instance_id) \
  --query 'Reservations[0].Instances[0].State.Name'

# 確認 SSM 代理連線
aws ssm describe-instance-information \
  --filters Key=InstanceIds,Values=$(terraform output -raw linux_instance_id) \
  --query 'InstanceInformationList[0].PingStatus'

# SSH 連線測試
$(terraform output -raw ssh_command) "echo 'connected'"
```

## 延伸用途

連接私有資源（如 Aurora）時，可在其他 env 的 `allowed_security_groups` 中加入：
```hcl
allowed_security_groups = [data.terraform_remote_state.linux.outputs.linux_security_group_id]
```

## 費用估算

| 資源 | 規格 | 費用 |
|------|------|------|
| EC2 Spot t3.micro | 720 hr/月 | ~$1.6/月 |
| EBS gp3 20GB | 長駐 | ~$1.6/月 |
| VPC / Subnet | 免費 | $0 |
| **合計** | | **~$3.2/月** |

> ⚠️ Spot instance 可能被中斷。若需穩定連線請設 `market_type = "on-demand"`（~$7.5/月）

## 關閉環境

```bash
# 停止（保留資源，停止計費 EC2）
aws ec2 stop-instances --instance-ids $(terraform output -raw linux_instance_id)

# 完全移除
terraform destroy
# ⚠️ Spot Request 需另至 AWS Console 手動取消
```

## 卡關提示

| 症狀 | 原因 | 解法 |
|------|------|------|
| SSH 連線逾時 | Security Group 未開 22 port | 確認 `my_ip` 正確 |
| SSM 無回應 | IAM Role 尚未就緒 | 等待 2-3 分鐘後重試 |
| Spot 無法建立 | 可用區容量不足 | 改 `market_type = "on-demand"` |
| Permission denied (publickey) | PEM 權限問題 | `chmod 400 *.pem` |
