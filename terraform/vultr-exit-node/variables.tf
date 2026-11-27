variable "region" {
  type        = string
  default     = "nrt"
  description = "Vultr 區域代碼；預設 nrt（東京）。"
}

variable "plan" {
  type        = string
  default     = "vc2-1c-1gb"
  description = "Vultr Cloud Compute 規格。"
}

variable "os_id" {
  type        = number
  default     = 1743
  description = "Vultr 作業系統 ID；預設 1743（Ubuntu 22.04 LTS x64）。"
}

variable "hostname" {
  type        = string
  default     = "vultr-tokyo-exit"
  description = "VM 與 Tailscale 使用的主機名稱。修改 Vultr hostname 會重建實例。"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.hostname))
    error_message = "hostname 必須是 1 到 63 字元的小寫英數字或連字號，且不能以連字號開頭或結尾。"
  }
}

variable "tailscale_auth_key" {
  type        = string
  sensitive   = true
  description = "一次性、非 ephemeral 的 Tailscale auth key；可用 TF_VAR_tailscale_auth_key 環境變數提供。"

  validation {
    condition     = length(trimspace(var.tailscale_auth_key)) > 0
    error_message = "請提供 Tailscale auth key。"
  }
}

variable "enable_ipv6" {
  type        = bool
  default     = true
  description = "是否為 Vultr VM 啟用 IPv6。"
}

variable "allow_tailscale_udp_41641" {
  type        = bool
  default     = false
  description = "是否開放公網 UDP/41641，供 Tailscale 嘗試直接連線；關閉時仍可經 DERP 中繼連線。"
}
