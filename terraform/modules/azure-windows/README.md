# Module: azure-windows 🔴 危險

> 建立 Azure Windows Server 2025 虛擬機器的可重用模組：Public IP、NIC-level NSG（RDP/WinRM）、Windows VM、密碼自動管理。
> 對標 AWS 的 `aws-windows` 模組，搭配 `azure-vnet` 使用。

**費用估算**：`Standard_B2s` ≈ $0.0416/hr（約 $0.25–0.50/次實驗）

> ⚠️ **練完請立即 `terraform destroy`**，Windows VM License 費用含在 VM 定價內，運行中持續計費。

---

## AWS vs Azure 對比

| 元素 | AWS (`aws-windows`) | Azure (`azure-windows`) |
|------|--------------------|-----------------------|
| 執行個體 | EC2 Windows Server 2025 | VM Windows Server 2025 |
| 防火牆 | Security Group（開放 RDP 3389）| NIC-level NSG（模組自建）|
| 認證方式 | Key Pair（解密 RDP 密碼）| Admin Password（直接設定）|
| 定價模型 | Spot / On-demand | On-demand（Azure 無 Windows Spot）|
| 連線方式 | RDP + mstsc | RDP + mstsc / Azure Bastion |

---

## 架構

```
Internet
    │  RDP :3389 (my_ip only, NIC-level NSG)
    │  WinRM :5985-5986 (enable_winrm = true 時)
    ▼
┌──────────────────────────────────────────────────┐
│  Resource Group                                  │
│                                                  │
│  Public IP (Static, Standard SKU)                │
│       │                                          │
│  ┌────┴──────────────────────────────────────┐   │
│  │  NIC                                      │   │
│  │  ├── NIC NSG: AllowRDP (3389)             │   │
│  │  │           AllowWinRM (5985-5986, 可選) │   │
│  │  └─► Windows Server 2025 Datacenter VM   │   │
│  │        size: Standard_B2s                 │   │
│  │        disk: 128 GB StandardSSD           │   │
│  │        Trusted Launch enabled             │   │
│  └───────────────────────────────────────────┘   │
│       (Subnet from azure-vnet)                   │
└──────────────────────────────────────────────────┘
```

> **NSG 設計說明**：`azure-windows` 在 NIC 層建立專屬 NSG（而非依賴 subnet NSG），
> 讓 Windows VM 的網路規則與 `azure-vnet` 模組解耦，方便在不同網路環境重用。

---

## 輸入變數

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `subscription_id` | 必填 | Azure Subscription ID |
| `resource_group_name` | 必填 | RG 名稱（用 `module.vnet.resource_group_name`）|
| `subnet_id` | 必填 | 子網路 ID（用 `values(module.vnet.public_subnet_ids)[0]`）|
| `my_ip` | 必填 | 你的公網 IP（CIDR，如 `1.2.3.4/32`）|
| `location` | `japaneast` | Azure 部署區域 |
| `name_prefix` | `az-win` | 資源名稱前綴 |
| `environment` | `dev` | 環境標籤 |
| `vm_size` | `Standard_B2s` | VM 規格（Windows 建議最少 2 vCPU）|
| `admin_username` | `azureuser` | 登入帳號（不可用 administrator / admin）|
| `admin_password` | `null` | RDP 密碼（null 時自動生成 20 字元強密碼）|
| `os_disk_size_gb` | `128` | OS 磁碟大小（最少 128 GB）|
| `os_image` | Windows Server 2025 Datacenter | 來源映像（object）|
| `create_public_ip` | `true` | 是否建立公開 IP |
| `enable_winrm` | `false` | 是否開放 WinRM (5985-5986) |
| `extra_inbound_ports` | `[]` | 額外開放給 my_ip 的 TCP port |
| `timezone` | `Tokyo Standard Time` | VM 時區 |

---

## 輸出值

| 輸出 | 說明 |
|------|------|
| `vm_id` | VM 資源 ID |
| `public_ip` | 公開 IP 位址 |
| `private_ip` | 私有 IP 位址 |
| `rdp_command` | RDP 連線指令（`mstsc /v:<ip>`）|
| `admin_username` | 登入帳號 |
| `admin_password` | RDP 密碼（sensitive）|
| `password_file_path` | 自動生成密碼的本地檔案路徑（sensitive）|
| `nsg_id` | NIC NSG 資源 ID |
| `nic_id` | NIC 資源 ID |

---

## 使用方式

### 搭配 azure-vnet 部署（推薦）

```hcl
module "vnet" {
  source          = "../../modules/azure-vnet"
  subscription_id = var.subscription_id
  name_prefix     = "my-env"
  my_ip           = var.my_ip
}

module "win" {
  source              = "../../modules/azure-windows"
  subscription_id     = var.subscription_id
  resource_group_name = module.vnet.resource_group_name
  subnet_id           = values(module.vnet.public_subnet_ids)[0]
  my_ip               = var.my_ip
  name_prefix         = "my-env"
  # admin_password 不填 → 自動生成，存至 my-env-password.txt
}
```

### 傳入自訂密碼

```hcl
module "win" {
  source              = "../../modules/azure-windows"
  subscription_id     = var.subscription_id
  resource_group_name = module.vnet.resource_group_name
  subnet_id           = values(module.vnet.public_subnet_ids)[0]
  my_ip               = var.my_ip
  admin_password      = var.admin_password   # 放在 terraform.tfvars（已 gitignore）
}
```

---

## 操作步驟

```bash
# 0. 確認 Azure CLI 已登入
az login
az account show --query id -o tsv

# 1. 初始化 → 格式化 → 驗證 → 預覽 → 部署
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

---

## 驗證

```bash
# 取得 RDP 連線指令
terraform output rdp_command

# 取得密碼（sensitive output 需加 -raw）
terraform output -raw admin_password

# Windows：直接執行 RDP
mstsc /v:$(terraform output -raw public_ip)

# 用 Azure CLI 確認 VM 狀態（等 provisioning 完成約 2-5 分鐘）
az vm show \
  --resource-group <resource_group_name> \
  --name <name_prefix>-vm \
  --query "provisioningState" -o tsv

# 查看自動生成的密碼檔（若 admin_password = null）
cat <name_prefix>-password.txt
```

---

## 清除資源

```bash
terraform destroy -auto-approve
```

---

## 檔案結構

```
azure-windows/
├── terraform.tf      # Provider + 版本約束（azurerm + random + local）
├── variables.tf      # 輸入變數
├── locals.tf         # common_tags + 密碼邏輯
├── main.tf           # Public IP、NIC NSG、NIC、Windows VM
├── password.tf       # 自動生成 random_password + 寫入本地檔案
├── outputs.tf        # 輸出值
├── .gitignore
└── README.md
```

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| RDP 連不上 | 確認 `my_ip` 為你目前的 IP；VM 首次啟動需 2-5 分鐘初始化 |
| 密碼不符複雜度 | Azure 密碼需含大小寫、數字、特殊符號各至少一個，長度 12-123 字元 |
| `admin_username` 錯誤 | 不可使用 `administrator`、`admin`、`root`、`guest` 等保留名稱 |
| Trusted Launch 不支援 | 改用 Windows Server 2019+ 映像；舊版（2016 以前）不支援 |
| apply 後 VM 一直 Creating | 正常現象，Windows VM 佈建需要 3-8 分鐘 |
| WinRM 連不上 | 需設 `enable_winrm = true`；模組僅開放 5986（HTTPS），VM 內需執行 `winrm quickconfig -transport:https` |
| VM 大小不可用 | 執行 `az vm list-sizes --location japaneast -o table` 確認可用規格 |
