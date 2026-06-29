#==============================================================
# env: azure-windows — Windows Server 2025 開發 / 跳板機
#
# 拓樸：
#   你的電腦 --RDP (3389)--> Windows VM (Public Subnet)
#                                  |
#                          (可延伸連接 Private 資源)
#                                  ↓
#                     Azure SQL / AKS nodes (Private Subnet)
#==============================================================

# ── 1. VNet & Subnets ──────────────────────────────────────

module "vnet" {
  source = "../../modules/azure-vnet"

  subscription_id = var.subscription_id
  location        = var.location
  name_prefix     = var.project
  environment     = var.environment
  my_ip           = var.my_ip

  vnet_cidr       = var.vnet_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

# ── 2. Windows VM (Bastion / Dev) ──────────────────────────
# 注意：RDP NSG 規則由 azure-windows module 在 NIC 層自動建立，
#       不需要在 azure-vnet 的 extra_public_ports 額外開放 3389

module "windows" {
  source = "../../modules/azure-windows"

  subscription_id = var.subscription_id
  location        = var.location
  name_prefix     = var.project
  environment     = var.environment
  my_ip           = var.my_ip

  resource_group_name = module.vnet.resource_group_name
  subnet_id           = values(module.vnet.public_subnet_ids)[0]
  vm_size             = var.vm_size
  os_disk_size_gb     = var.os_disk_size_gb
  admin_password      = var.admin_password
  enable_winrm        = var.enable_winrm
  timezone            = var.timezone
}
