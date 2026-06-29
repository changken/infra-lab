variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID."
}

variable "location" {
  type        = string
  default     = "japaneast"
  description = "Azure region for all resources."
}

variable "name_prefix" {
  type        = string
  default     = "az-win"
  description = "Prefix for all resource names to avoid collision across environments."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Deployment environment (e.g. dev, staging, prod)."
}

# ── 必填：網路資訊（與 azure-vnet 模組搭配）────────────────────
# 傳入方式範例：
#   resource_group_name = module.vnet.resource_group_name
#   subnet_id           = values(module.vnet.public_subnet_ids)[0]

variable "resource_group_name" {
  type        = string
  description = "Name of the Resource Group to deploy resources into."
}

variable "subnet_id" {
  type        = string
  description = "ID of the subnet to attach the NIC. Use values(module.vnet.public_subnet_ids)[0]."
}

# ── 安全性：NIC-level NSG ─────────────────────────────────────

variable "my_ip" {
  type        = string
  description = "Your public IP in CIDR notation for RDP/WinRM access (e.g. 1.2.3.4/32)."
  validation {
    condition     = can(cidrhost(var.my_ip, 0)) && tonumber(split("/", var.my_ip)[1]) >= 16
    error_message = "Must be a valid CIDR block with prefix length >= 16 (e.g. 1.2.3.4/32). 0.0.0.0/0 is not allowed."
  }
}

variable "extra_inbound_ports" {
  type        = list(number)
  default     = []
  description = "Extra TCP ports allowed from my_ip on the NIC NSG (e.g. [8080])."
}

# ── VM 規格 ────────────────────────────────────────────────────

variable "vm_size" {
  type        = string
  default     = "Standard_B2s"
  description = "Azure VM size. Windows Server 需至少 2 vCPU / 4 GB RAM。"
}

variable "admin_username" {
  type        = string
  default     = "azureuser"
  description = "Admin username for the VM. 不可使用 'administrator' 或 'admin'。"
  validation {
    condition     = !contains(["administrator", "admin", "root", "guest"], lower(var.admin_username))
    error_message = "admin_username 不可使用保留名稱 (administrator, admin, root, guest)。"
  }
}

variable "admin_password" {
  type        = string
  default     = null
  description = "Admin password (12–123 字元，需含大小寫、數字、特殊符號各至少一個)。If null, auto-generated (stored in tfstate — test only)."
  sensitive   = true
}

variable "os_disk_size_gb" {
  type        = number
  default     = 128
  description = "OS disk size in GB (Windows Server 2025 minimum is 128 GB)."
  validation {
    condition     = var.os_disk_size_gb >= 128
    error_message = "os_disk_size_gb must be at least 128 GB for Windows Server."
  }
}

variable "os_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-azure-edition"
    version   = "latest"
  }
  description = "Source image reference. Default: Windows Server 2025 Datacenter Azure Edition."
}

variable "create_public_ip" {
  type        = bool
  default     = true
  description = "Whether to create and attach a public IP to the VM."
}

variable "enable_winrm" {
  type        = bool
  default     = false
  description = "Whether to allow WinRM (TCP 5985–5986) from my_ip on the NIC NSG."
}

variable "timezone" {
  type        = string
  default     = "Tokyo Standard Time"
  description = "VM timezone. Use Windows timezone names (e.g. 'UTC', 'Tokyo Standard Time')."
}
