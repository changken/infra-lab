# AWS Windows Server 2025 — Spot Instance (Terraform)

使用 Terraform 在 AWS 上快速建立 **Windows Server 2025 Spot Instance**，內含 CloudWatch Agent 監控與 SSM 管理。

## 架構概覽

| 元件 | 說明 |
|------|------|
| EC2 Spot Instance | `m5a.xlarge`，一次性 Spot |
| Networking | Default VPC + Security Group（僅開放 RDP） |
| IAM | SSM + CloudWatch Agent 權限 |
| CloudWatch Agent | CPU / Memory / Disk / Windows Event Log |
| Key Pair | 自動產生 RSA 4096 金鑰 |

## 前置條件

- [Terraform](https://www.terraform.io/) >= 1.0
- AWS CLI 已設定好 credentials（`aws configure`）

## 快速開始

```bash
# 1. Clone
git clone https://github.com/<your-username>/aws-win-server-2026.git
cd aws-win-server-2026

# 2. 設定變數
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入你的公網 IP

# 3. 部署
terraform init
terraform plan
terraform apply
```

## 取得 RDP 連線資訊

```bash
# 查看公網 IP
terraform output public_ip

# 取得 Windows 密碼（需等待數分鐘讓 Instance 初始化完成）
eval $(terraform output -raw rdp_password_command)
```

## 清除資源

```bash
terraform destroy
```

## 檔案結構

```
├── main.tf                  # Provider + EC2 Instance
├── variables.tf             # 變數定義
├── outputs.tf               # 輸出值
├── network.tf               # VPC / Security Group
├── iam.tf                   # IAM Role & Policy
├── cloudwatch.tf            # CloudWatch Agent 設定
├── keypair.tf               # Key Pair 自動產生
└── terraform.tfvars.example # 變數範本
```

## License

MIT
