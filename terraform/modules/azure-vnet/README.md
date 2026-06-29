# Module: azure-vnet 🟢 免費

> 建立 Azure 網路基礎設施的可重用模組：Resource Group、Virtual Network、Public / Private Subnets、Network Security Groups。
> 對標 AWS 的 `aws-vpc` 模組。

**費用估算**：$0（VNet、Subnet、NSG 均為免費資源）

---

## AWS vs Azure 對比

| 元素 | AWS (`aws-vpc`) | Azure (`azure-vnet`) |
|------|----------------|---------------------|
| 網路隔離單元 | VPC | Virtual Network (VNet) |
| 子網路 | Subnet（需綁定 AZ）| Subnet（不需指定 AZ）|
| 防火牆 | Security Group（instance 層）| NSG（subnet 或 NIC 層）|
| 路由 | Route Table（明確建立）| 自動預設路由（不需手動建）|
| 資源容器 | 無（用 Tags 分類）| Resource Group（必填）|

---

## 架構

```
┌──────────────────────────────────────────────────────┐
│  Resource Group  (${name_prefix}-rg)                 │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  Virtual Network  10.0.0.0/16                  │  │
│  │                                                │  │
│  │  ┌─────────────────┐  ┌─────────────────────┐ │  │
│  │  │ Public Subnet   │  │ Private Subnet      │ │  │
│  │  │ 10.0.1.0/24     │  │ 10.0.11.0/24        │ │  │
│  │  │ [public-nsg] ←──┼──┼── RDP/SSH from my_ip│ │  │
│  │  └─────────────────┘  └─────────────────────┘ │  │
│  │                          [private-nsg]         │  │
│  │                          VNet 內部流量 only     │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

---

## 輸入變數

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `subscription_id` | 必填 | Azure Subscription ID |
| `location` | `japaneast` | Azure 部署區域 |
| `name_prefix` | `infra-lab` | 資源名稱前綴 |
| `environment` | `dev` | 環境標籤 |
| `vnet_cidr` | `10.0.0.0/16` | VNet 位址空間 |
| `public_subnets` | `{ "public-1" = "10.0.1.0/24" }` | 公開子網路 map |
| `private_subnets` | `{ "private-1" = "10.0.11.0/24" }` | 私有子網路 map |
| `my_ip` | 必填 | 你的公網 IP（CIDR，如 `1.2.3.4/32`）|
| `create_resource_group` | `true` | false 時傳入已存在的 RG |
| `resource_group_name` | `null` | 已存在的 RG 名稱（create_resource_group = false 時用）|
| `extra_public_ports` | `[]` | 額外開放給 my_ip 的 TCP port（如 `[80, 3389]`）|

---

## 輸出值

| 輸出 | 說明 |
|------|------|
| `resource_group_name` | Resource Group 名稱 |
| `resource_group_location` | Resource Group 所在區域 |
| `vnet_id` | VNet ID |
| `vnet_name` | VNet 名稱 |
| `public_subnet_ids` | `map(name => subnet_id)`（公開子網路）|
| `private_subnet_ids` | `map(name => subnet_id)`（私有子網路）|
| `public_nsg_id` | 公開 NSG ID |
| `private_nsg_id` | 私有 NSG ID |

---

## 使用方式

### 獨立部署

```bash
# 0. 確認 Azure CLI 已登入
az login
az account show --query id -o tsv   # 取得 subscription_id

# 1. 複製並填寫變數
cp terraform.tfvars.example terraform.tfvars

# 2. 初始化 → 格式化 → 驗證 → 預覽 → 部署
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

### 作為模組呼叫

```hcl
module "vnet" {
  source          = "../../modules/azure-vnet"
  subscription_id = var.subscription_id
  name_prefix     = "my-env"
  my_ip           = "1.2.3.4/32"

  # 多組子網路
  public_subnets  = { "pub-1" = "10.0.1.0/24", "pub-2" = "10.0.2.0/24" }
  private_subnets = { "prv-1" = "10.0.11.0/24" }

  # Windows VM 需要額外開放 RDP
  extra_public_ports = [3389]
}

# 取用輸出傳給其他模組
resource_group_name = module.vnet.resource_group_name
subnet_id           = values(module.vnet.public_subnet_ids)[0]
```

---

## 驗證

```bash
# 查看所有 outputs
terraform output

# 用 Azure CLI 確認 VNet 已建立
az network vnet list --query "[].{name:name, addressSpace:addressSpace}" -o table

# 確認 Subnet
az network vnet subnet list \
  --resource-group $(terraform output -raw resource_group_name) \
  --vnet-name $(terraform output -raw vnet_name) \
  -o table

# 確認 NSG 規則
az network nsg list \
  --resource-group $(terraform output -raw resource_group_name) \
  -o table
```

---

## 清除資源

```bash
terraform destroy -auto-approve
```

---

## 檔案結構

```
azure-vnet/
├── terraform.tf      # Provider + 版本約束
├── variables.tf      # 輸入變數
├── locals.tf         # common_tags + RG 解析
├── main.tf           # RG、VNet、Subnet、NSG、NSG 關聯
├── outputs.tf        # 輸出值
├── .gitignore
└── README.md
```

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `subscription_id` 錯誤 | 執行 `az account show --query id -o tsv` 取得正確值 |
| NSG 規則不生效 | Subnet NSG 關聯需要等 1-2 分鐘傳播；另確認 my_ip 為正確的 CIDR |
| Subnet CIDR 衝突 | public 和 private subnet CIDR 不可重疊，且都必須落在 vnet_cidr 範圍內 |
| `resource_group_name` 為 null | `create_resource_group = false` 時必須明確填入 `resource_group_name` |
