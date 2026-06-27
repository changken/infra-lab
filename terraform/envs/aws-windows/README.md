# aws-windows — Windows Server 2025 開發 / 跳板機

🟡 **費用等級：注意** — m5a.xlarge Spot ~$0.04/hr（約 $29/月長駐）

長駐環境：Windows Server 2025 EC2，作為 RDP 開發環境與跳板機。
可延伸連接私有子網路中的 RDS、Aurora 等資源。

## 架構

```
你的電腦
    │
    │ RDP :3389
    ▼
┌─────────────────────────────────┐
│  Public Subnet (10.30.1.0/24)  │
│  Windows Server 2025 Spot      │
│  m5a.xlarge (4vCPU / 16GB)     │
│  - SSM Session Manager          │
│  - CloudWatch Agent             │
│  - 50GB gp3 EBS                 │
└─────────────────────────────────┘
    │
    │ (可延伸)
    ▼
┌─────────────────────────────────┐
│  Private Subnet                 │
│  RDS / Aurora / 其他資源        │
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

### RDP（傳統遠端桌面）
```bash
# 1. 取得 RDP 密碼指令
terraform output -raw rdp_password_command

# 2. 執行輸出的指令（等待約 4 分鐘讓 instance 初始化）
aws ec2 get-password-data \
  --instance-id <instance_id> \
  --priv-launch-key <path/to/key.pem> \
  --query 'PasswordData' --output text

# 3. 開啟 RDP 連線
#    IP:   terraform output -raw windows_public_ip
#    Port: 3389
#    User: Administrator
```

### SSM Session Manager（免開 RDP port，推薦）
```bash
terraform output windows_instance_id
aws ssm start-session --target <instance_id>
```

## 驗證

```bash
# 確認 instance 狀態
aws ec2 describe-instances \
  --instance-ids $(terraform output -raw windows_instance_id) \
  --query 'Reservations[0].Instances[0].State.Name'

# 確認 SSM 代理連線（約 2-3 分鐘後就緒）
aws ssm describe-instance-information \
  --filters Key=InstanceIds,Values=$(terraform output -raw windows_instance_id) \
  --query 'InstanceInformationList[0].PingStatus'
```

## 費用估算

| 資源 | 規格 | 費用 |
|------|------|------|
| EC2 Spot m5a.xlarge | 依使用時數 | ~$0.04/hr |
| EBS gp3 50GB | 長駐 | ~$4/月 |
| VPC / Subnet | 免費 | $0 |
| **長駐合計** | 720hr/月 | **~$33/月** |
| **按需使用** | 40hr/月 | **~$6/月** |

> 輕量開發可改用 `t3.medium`（~$0.013/hr），降至約 ~$13/月長駐

> ⚠️ Spot instance 可能被中斷。需穩定 RDP 工作時改設 `market_type = "on-demand"`

## 節省費用

```bash
# 停止（保留 EBS，停止 EC2 計費）
aws ec2 stop-instances \
  --instance-ids $(terraform output -raw windows_instance_id)

# 重新啟動
aws ec2 start-instances \
  --instance-ids $(terraform output -raw windows_instance_id)

# 完全移除
terraform destroy
# ⚠️ Spot Request 需另至 AWS Console 手動取消
```

## 與 aws-aurora-windows-bastion 的差異

| | `aws-windows` | `aws-aurora-windows-bastion` |
|--|---------------|------------------------------|
| 用途 | 純 Windows 開發 / 跳板 | Windows + Aurora PostgreSQL |
| 費用 | ~$33/月（長駐） | ~$33 + Aurora ACU |
| 適合 | 不需要 DB 的場景 | 需要連接 Aurora 的場景 |

## 卡關提示

| 症狀 | 原因 | 解法 |
|------|------|------|
| RDP 連線逾時 | Security Group 未開 3389 | 確認 `my_ip` 正確 |
| 密碼取得失敗 | Instance 尚未初始化完成 | 等待 4 分鐘後重試 |
| SSM 無回應 | IAM Role 尚未就緒 | 等待 2-3 分鐘後重試 |
| Spot 無法建立 | 可用區容量不足 | 改 `market_type = "on-demand"` |
