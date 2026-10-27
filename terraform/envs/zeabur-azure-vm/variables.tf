variable "subscription_id" {
  description = "Azure subscription ID（azurerm v4 必填）"
  type        = string
}

variable "project" {
  description = "命名前綴"
  type        = string
  default     = "zeabur"
}

variable "environment" {
  description = "環境名稱 (dev/stg/prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "japaneast"
}

variable "tags" {
  description = "額外 tags"
  type        = map(string)
  default     = {}
}

# ---------- Network ----------
variable "vnet_cidr" {
  description = "VNet address space"
  type        = string
  default     = "172.28.0.0/16"
}

variable "subnets" {
  description = "Subnet 定義 (name => cidr)"
  type        = map(string)
  default = {
    subnet1 = "172.28.1.0/24"
    subnet2 = "172.28.2.0/24"
  }
}

variable "vm_subnet_key" {
  description = "VM 放在哪個 subnet（對應 var.subnets 的 key）"
  type        = string
  default     = "subnet1"
}

variable "allowed_source_prefix_ssh" {
  description = "NSG inbound 允許的來源，預設全開。正式環境建議至少把 22/6443 鎖到 Zeabur / 你自己的 IP"
  type        = string
  default     = "*"
}


variable "allowed_source_prefix" {
  description = "NSG inbound 允許的來源，預設全開。正式環境建議至少把 22/6443 鎖到 Zeabur / 你自己的 IP"
  type        = string
  default     = "*"
}

# ---------- VM ----------
variable "vm_size" {
  description = "VM size。Standard_B1ms = 1 vCPU / 2 GiB（剛好壓最低需求）"
  type        = string
  default     = "Standard_B1ms"
}

variable "admin_username" {
  description = "VM admin user（Azure 不允許 root；SSH key 建立的 admin 預設 NOPASSWD sudo）"
  type        = string
  default     = "azureuser"
}

variable "os_disk_size_gb" {
  description = "OS disk 大小 (GB)，Zeabur 會拉 container image，別太小"
  type        = number
  default     = 64
}

variable "os_disk_type" {
  description = "OS disk SKU"
  type        = string
  default     = "StandardSSD_LRS"
}
