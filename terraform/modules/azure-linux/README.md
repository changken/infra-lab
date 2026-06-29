# Module: azure-linux 🟡 注意

> 建立 Azure Ubuntu 24.04 LTS 虛擬機器的可重用模組：Public IP、NIC、Linux VM、SSH 金鑰自動管理。
> 對標 AWS 的 `aws-linux` 模組，搭配 `azure-vnet` 使用。

**費用估算**：`Standard_B1s` ≈ $0.0104/hr（約 $0.10–0.25/次實驗）

> ⚠️ 練完請執行 `terraform destroy`，VM 運行中持續計費。

---

## AWS vs Azure 對比

| 元素 | AWS (`aws-linux`) | Azure (`azure-linux`) |
|------|------------------|-----------------------|
| 執行個體 | EC2 (Amazon Linux 2023) | VM (Ubuntu 24.04 LTS) |
| 防火牆 | Security Group（instance 層）| NSG（由 `azure-vnet` 建立）|
| SSH 金鑰 | Key Pair（PEM 檔）| Admin SSH Key（公鑰注入）|
| 管理通道 | SSM Session Manager | Azure Bastion / 直連 SSH |
| 免費額度 | t2.micro 750hr/月 | B1s 750hr/月（首年）|

---

## 架構

```
Internet
    │  SSH :22 (my_ip only, via azure-vnet NSG)
    ▼
┌──────────────────────────────────────────┐
│  Resource Group                          │
│                                          │
│  Public IP (Static, Standard SKU)        │
│       │                                  │
│  ┌────┴──────────────────────────────┐   │
│  │  NIC                              │   │
│  │  └─► Ubuntu 24.04 LTS VM         │   │
│  │        size: Standard_B1s         │   │
│  │        disk: 30 GB StandardSSD    │   │
│  │        Trusted Launch enabled     │   │
│  └───────────────────────────────────┘   │
│       (Subnet from azure-vnet)           │
└──────────────────────────────────────────┘
```

---

## 輸入變數

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `subscription_id` | 必填 | Azure Subscription ID |
| `resource_group_name` | 必填 | RG 名稱（用 `module.vnet.resource_group_name`）|
| `subnet_id` | 必填 | 子網路 ID（用 `values(module.vnet.public_subnet_ids)[0]`）|
| `location` | `japaneast` | Azure 部署區域 |
| `name_prefix` | `az-linux` | 資源名稱前綴 |
| `environment` | `dev` | 環境標籤 |
| `vm_size` | `Standard_B1s` | VM 規格 |
| `admin_username` | `azureuser` | 登入帳號 |
| `admin_ssh_public_key` | `null` | SSH 公鑰（null 時自動生成）|
| `os_disk_size_gb` | `30` | OS 磁碟大小（最少 30 GB）|
| `os_image` | Ubuntu 24.04 LTS | 來源映像（object）|
| `create_public_ip` | `true` | 是否建立公開 IP |
| `user_data` | `null` | Cloud-init 腳本（純文字）|

---

## 輸出值

| 輸出 | 說明 |
|------|------|
| `vm_id` | VM 資源 ID |
| `public_ip` | 公開 IP 位址 |
| `private_ip` | 私有 IP 位址 |
| `ssh_command` | 直接可用的 SSH 連線指令 |
| `private_key_path` | 自動生成金鑰的本地路徑（sensitive）|
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

module "vm" {
  source              = "../../modules/azure-linux"
  subscription_id     = var.subscription_id
  resource_group_name = module.vnet.resource_group_name
  subnet_id           = values(module.vnet.public_subnet_ids)[0]
  name_prefix         = "my-env"
  # admin_ssh_public_key 不填 → 自動生成金鑰，存至 my-env-key.pem
}
```

### 傳入自己的 SSH 公鑰

```hcl
module "vm" {
  source               = "../../modules/azure-linux"
  subscription_id      = var.subscription_id
  resource_group_name  = module.vnet.resource_group_name
  subnet_id            = values(module.vnet.public_subnet_ids)[0]
  admin_ssh_public_key = file("~/.ssh/id_rsa.pub")
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
# 取得 SSH 連線指令
terraform output ssh_command

# 直接連線（自動生成金鑰時）
eval "$(terraform output -raw ssh_command)"

# 或手動連線
ssh -i ./my-env-key.pem azureuser@$(terraform output -raw public_ip)

# 用 Azure CLI 確認 VM 狀態
az vm show \
  --resource-group $(terraform output -raw resource_group_name 2>/dev/null || echo "my-env-rg") \
  --name <name_prefix>-vm \
  --query "provisioningState" -o tsv
```

---

## 清除資源

```bash
terraform destroy -auto-approve
```

---

## 檔案結構

```
azure-linux/
├── terraform.tf      # Provider + 版本約束（azurerm + tls + local）
├── variables.tf      # 輸入變數
├── locals.tf         # common_tags + SSH 金鑰邏輯
├── main.tf           # Public IP、NIC、Linux VM
├── keypair.tf        # 自動生成 RSA 4096 金鑰
├── outputs.tf        # 輸出值
├── .gitignore
└── README.md
```

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| SSH 連不上 | 確認 `azure-vnet` 的 NSG 有開 port 22（預設已開），且 `my_ip` 為你目前的 IP |
| `*.pem` 權限錯誤 | 執行 `chmod 600 <name_prefix>-key.pem` |
| apply 後 public_ip 是 null | `create_public_ip = false`，改為 true 或用 Bastion 連線 |
| Trusted Launch 不支援 | 切換 os_image 到 Ubuntu 20.04+ 或 Windows Server 2019+，舊版不支援 |
| VM 大小不可用 | 執行 `az vm list-sizes --location japaneast -o table` 確認區域可用規格 |
