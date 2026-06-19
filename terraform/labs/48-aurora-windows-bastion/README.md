# Lab 48 - Aurora PostgreSQL + Windows Spot Bastion

## 架構概覽

```
你的電腦
   │
   │ RDP 3389（限制來自 my_ip）
   ▼
┌──────────────────────────────────────────────────┐
│                  自訂 VPC (10.10.0.0/16)          │
│                                                  │
│  Public Subnet (10.10.1.0/24)                   │
│  ┌──────────────────────────┐                   │
│  │  Windows Server 2025     │                   │
│  │  Spot Instance (Bastion) │                   │
│  └────────────┬─────────────┘                   │
│               │ PostgreSQL 5432                 │
│               │ (僅允許此 SG 連入)               │
│  Private Subnet (10.10.2.0/24)                  │
│  ┌──────────────────────────┐                   │
│  │  Aurora PostgreSQL       │                   │
│  │  Serverless v2 (0.5 ACU) │                   │
│  └──────────────────────────┘                   │
└──────────────────────────────────────────────────┘
```

## 使用的 Modules

| Module | 用途 |
|--------|------|
| `aws-vpc` | 建立自訂 VPC、Public/Private Subnet |
| `aws-windows-spot` | Windows Bastion，掛到 Public Subnet |
| `aws-aurora-postgresql` | Aurora Serverless v2，放在 Private Subnet |

## 快速開始

### 1. 準備設定檔

```bash
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入：
#   my_ip       = "你的公網IP/32"
#   db_password = "高強度密碼"
```

### 2. 部署

```bash
terraform init
terraform plan
terraform apply
```

### 3. 連線到 Aurora

```
terraform apply 完成後，查看 outputs：

  windows_public_ip  → RDP 連線 IP
  aurora_endpoint    → PostgreSQL 位址（在 Windows 上使用）
```

**步驟**：
1. 以 RDP 連入 Windows Bastion（`windows_public_ip:3389`）
2. 在 Windows 上安裝 [DBeaver](https://dbeaver.io/) 或 [pgAdmin](https://www.pgadmin.org/)
3. 使用 `aurora_endpoint`（Port 5432）連接 Aurora

### 4. 清除資源

```bash
terraform destroy
```

## 安全說明

- Aurora 放在 **Private Subnet**，完全不對外
- Aurora SG 只允許 Windows Bastion 的 SG 連入 5432
- Windows RDP 只允許 `my_ip` 連入 3389
- `terraform.tfvars` 已加入 `.gitignore`，禁止 commit 密碼
