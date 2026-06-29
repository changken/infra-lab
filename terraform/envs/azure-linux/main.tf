#==============================================================
# env: azure-linux — Ubuntu 24.04 LTS 開發 / 跳板機
#
# 拓樸：
#   你的電腦 --SSH (22)--> Ubuntu VM (Public Subnet)
#                               |
#                       (可延伸連接 Private 資源)
#                               ↓
#                  Azure SQL / AKS nodes (Private Subnet)
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

# ── 2. Linux VM (Bastion / Dev) ────────────────────────────

module "linux" {
  source = "../../modules/azure-linux"

  subscription_id = var.subscription_id
  location        = var.location
  name_prefix     = var.project
  environment     = var.environment

  resource_group_name  = module.vnet.resource_group_name
  subnet_id            = values(module.vnet.public_subnet_ids)[0]
  vm_size              = var.vm_size
  os_disk_size_gb      = var.os_disk_size_gb
  admin_ssh_public_key = var.admin_ssh_public_key
}
