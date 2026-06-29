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
