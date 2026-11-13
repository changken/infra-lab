variable "region" {
  description = "OCI region"
  type        = string
  default     = "ap-singapore-1"
}

variable "compartment_id" {
  description = "homelab compartment OCID（取自 oci-governance 的 output）"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "NSG 允許 SSH 的來源 CIDR（你的家用／辦公 IP，/32）"
  type        = string
}

variable "subnet_ipv6_cidr_block" {
  description = "public subnet 的 IPv6 /64（取自 VCN 的 Oracle 配發前綴，Console 啟用 IPv6 後才會產生）"
  type        = string
}

variable "vcn_cidr" {
  description = "VCN 的 IPv4 CIDR"
  type        = string
}

variable "subnet_cidr" {
  description = "public subnet 的 IPv4 CIDR（k3s 節點互通規則的來源也用此值）"
  type        = string
}

variable "vcn_name" {
  description = "VCN display name"
  type        = string
}

variable "vcn_dns_label" {
  description = "VCN DNS label（小寫英數）"
  type        = string
}

variable "igw_name" {
  description = "Internet Gateway display name"
  type        = string
}

variable "route_table_name" {
  description = "public subnet 使用的 route table display name"
  type        = string
}

variable "subnet_name" {
  description = "public subnet display name"
  type        = string
}

variable "subnet_dns_label" {
  description = "public subnet DNS label（小寫英數）"
  type        = string
}

variable "nsg_name" {
  description = "NSG display name"
  type        = string
}
