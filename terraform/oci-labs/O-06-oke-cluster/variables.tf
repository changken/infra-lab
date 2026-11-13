variable "region" {
  description = "OCI region"
  type        = string
  default     = "ap-singapore-1"
}

variable "tenancy_id" {
  description = "Tenancy OCID（查 Availability Domain 用）"
  type        = string
}

variable "compartment_id" {
  description = "homelab compartment OCID（envs/oci-governance 的 output）"
  type        = string
}

variable "allowed_cidr" {
  description = "你的對外 IP（/32）：用於 K8s API(6443)、SSH(22)、LB(80/443)"
  type        = string
}

variable "ssh_public_key" {
  description = "節點 SSH 公鑰"
  type        = string
}

variable "name_prefix" {
  description = "資源名稱前綴"
  type        = string
  default     = "o04-oke"
}

variable "vcn_cidr" {
  description = "Lab 專用 VCN CIDR（避開 K8s 預設 pod 10.244.0.0/16 與 service 10.96.0.0/16）"
  type        = string
  default     = "10.20.0.0/16"
}

variable "kubernetes_version" {
  description = "K8s 版本；需有對應的 aarch64 OKE image（可用 oci ce node-pool-options get 查）"
  type        = string
  default     = "v1.36.4"
}

variable "cluster_type" {
  description = "BASIC_CLUSTER（control plane 免費）或 ENHANCED_CLUSTER（約 US$0.10/hr）"
  type        = string
  default     = "BASIC_CLUSTER"

  validation {
    condition     = contains(["BASIC_CLUSTER", "ENHANCED_CLUSTER"], var.cluster_type)
    error_message = "cluster_type 只能是 BASIC_CLUSTER 或 ENHANCED_CLUSTER。"
  }
}

variable "node_count" {
  description = "Worker node 數量"
  type        = number
  default     = 2

  # 💰 Always Free A1 總額 4 OCPU；envs/oci-linux 的實例已佔 1 OCPU，
  #    （2026-11 已擴大為 2 OCPU）本 lab 最多只能用 2 OCPU。超過會直接計費（PAYG 帳號沒有硬性上限）。
  # ⚠️ 此護欄只適用 A1。目前改用 E4（付費 shape）而暫時停用；改回 A1 時請取消註解。
  #    使用 E4 時沒有任何自動護欄，節點數與規格請自行控管。
  /*validation {
    condition     = var.node_count * var.node_ocpus <= 2
    error_message = "node_count * node_ocpus 不可超過 2（A1 Always Free 4 OCPU 已被 oci-linux 佔用 2）。"
  }*/
}

variable "node_ocpus" {
  description = "每個節點的 OCPU"
  type        = number
  default     = 1
}

variable "node_memory_gbs" {
  description = "每個節點的記憶體（GB）"
  type        = number
  default     = 6

  # A1 Always Free 24 GB；oci-linux 已用 12 GB，本 lab 最多 12 GB
  /*validation {
    condition     = var.node_count * var.node_memory_gbs <= 12
    error_message = "node_count * node_memory_gbs 不可超過 12（A1 Always Free 24 GB 已被 oci-linux 佔用 12）。"
  }*/
}

variable "node_boot_volume_gbs" {
  description = "每個節點的 boot volume（GB，OKE 最小 50）。Always Free 總額 200 GB，oci-linux 已用 47"
  type        = number
  default     = 50
}
