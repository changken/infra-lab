# ── 全域 ──────────────────────────────────────────────────

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID（執行 az account show --query id -o tsv 取得）"
}

variable "location" {
  type        = string
  default     = "japaneast"
  description = "Azure 部署區域"
}

variable "project" {
  type        = string
  default     = "az-linux-bastion"
  description = "專案名稱前綴，用於所有資源命名"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "環境標籤"
}

# ── 網路 ──────────────────────────────────────────────────

variable "my_ip" {
  type        = string
  description = "你的公網 IP（CIDR 格式），用於限制 SSH 連入。例如：1.2.3.4/32"
  validation {
    condition     = can(cidrhost(var.my_ip, 0)) && tonumber(split("/", var.my_ip)[1]) >= 16
    error_message = "必須是合法的 CIDR 格式且 prefix >= 16，例如 1.2.3.4/32"
  }
}

variable "vnet_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "public_subnets" {
  type    = map(string)
  default = { "public-1" = "10.40.1.0/24" }
}

variable "private_subnets" {
  type    = map(string)
  default = { "private-1" = "10.40.11.0/24" }
}

variable "public_open_ports" {
  type        = list(string)
  default     = ["22", "80", "443", "4222", "6443", "30000-32767"]
  description = "對外全開（0.0.0.0/0）的 TCP port / port range。⚠️ 這些 port 對整個網際網路開放，僅限刻意公開的服務（如 k3s API、NodePort）。22 會額外疊加一條全開規則，AllowSSH（限 my_ip）仍保留。"
}

# ── Linux VM ───────────────────────────────────────────────

variable "vm_size" {
  type        = string
  default     = "Standard_B1s"
  description = "Azure VM 規格（Free Tier 等級：Standard_B1s ~$0.01/hr）"
}

variable "os_disk_size_gb" {
  type        = number
  default     = 30
  description = "OS 磁碟大小 GB（最少 30）"
}

variable "admin_ssh_public_key" {
  type        = string
  default     = null
  description = "SSH 公鑰（OpenSSH 格式）。不填則自動生成金鑰，私鑰存至本地 .pem 檔"
  sensitive   = true
}

# ── Spot VM（選用，預設關閉）─────────────────────────────────────
# ⚠️ 這台是常駐跳板機，開啟 Spot 會導致隨時可能斷線，僅建議在
#    改做短期、可容忍中斷的實驗環境時開啟。

variable "enable_spot" {
  type        = bool
  default     = false
  description = "是否以 Spot 模式部署 VM（不建議用於常駐跳板機）"
}

variable "spot_max_price" {
  type        = number
  default     = -1
  description = "Spot 最高出價（USD/hr）。-1 = 願意支付到隨需價格"
}

variable "spot_eviction_policy" {
  type        = string
  default     = "Deallocate"
  description = "Spot VM 被回收時的處置：Deallocate 或 Delete"
}
