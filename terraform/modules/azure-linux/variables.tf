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
  default     = "az-linux"
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

# ── VM 規格 ────────────────────────────────────────────────────

variable "vm_size" {
  type        = string
  default     = "Standard_B1s"
  description = "Azure VM size (e.g. Standard_B1s, Standard_B2s)."
}

variable "admin_username" {
  type        = string
  default     = "azureuser"
  description = "Admin username for the VM."
}

variable "admin_ssh_public_key" {
  type        = string
  default     = null
  description = "SSH public key (OpenSSH format). If null, a key pair is auto-generated (private key saved to local file — only for test environments)."
  sensitive   = true
}

variable "os_disk_size_gb" {
  type        = number
  default     = 30
  description = "OS disk size in GB."
  validation {
    condition     = var.os_disk_size_gb >= 30
    error_message = "os_disk_size_gb must be at least 30 GB."
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
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  description = "Source image reference for the OS. Default: Ubuntu 24.04 LTS."
}

variable "create_public_ip" {
  type        = bool
  default     = true
  description = "Whether to create and attach a public IP to the VM."
}

variable "user_data" {
  type        = string
  default     = null
  description = "Cloud-init script content (plain text). Will be base64-encoded automatically."
}

# ── Spot VM（選用，預設關閉）─────────────────────────────────────
# ⚠️ Spot VM 可能隨時因容量不足或超過出價上限被回收（evict），
#    不適合當作常駐用途（例如跳板機），僅建議用於可容忍中斷的
#    短期實驗 / 可重跑的 workload。

variable "enable_spot" {
  type        = bool
  default     = false
  description = "是否以 Spot 模式部署（有折扣但可能隨時被回收）。不建議用於常駐跳板機。"
}

variable "spot_max_price" {
  type        = number
  default     = -1
  description = "Spot 最高出價（USD/hr）。-1 表示願意支付到隨需（on-demand）價格，僅會因容量不足被回收，不會因價格被回收。僅在 enable_spot = true 時生效。"
}

variable "spot_eviction_policy" {
  type        = string
  default     = "Deallocate"
  description = "Spot VM 被回收時的處置：Deallocate（保留磁碟，停止計費運算但磁碟仍計費，可之後重新啟動）或 Delete（VM 與磁碟一併刪除）。僅在 enable_spot = true 時生效。"
  validation {
    condition     = contains(["Deallocate", "Delete"], var.spot_eviction_policy)
    error_message = "spot_eviction_policy 必須是 Deallocate 或 Delete。"
  }
}
