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
  default     = "infra-lab"
  description = "Prefix for all resource names to avoid collision across environments."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Deployment environment (e.g. dev, staging, prod)."
}

variable "vnet_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Address space of the Virtual Network."
  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0))
    error_message = "vnet_cidr must be a valid CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "public_subnets" {
  type        = map(string)
  default     = { "public-1" = "10.0.1.0/24" }
  description = "Map of public subnet name => CIDR. E.g. { \"public-1\" = \"10.0.1.0/24\" }"
}

variable "private_subnets" {
  type        = map(string)
  default     = { "private-1" = "10.0.11.0/24" }
  description = "Map of private subnet name => CIDR. E.g. { \"private-1\" = \"10.0.11.0/24\" }"
}

variable "my_ip" {
  type        = string
  description = "Your public IP in CIDR notation for NSG inbound rules (e.g. 1.2.3.4/32)."
  validation {
    condition     = can(cidrhost(var.my_ip, 0)) && tonumber(split("/", var.my_ip)[1]) >= 16
    error_message = "Must be a valid CIDR block with prefix length >= 16 (e.g. 1.2.3.4/32). 0.0.0.0/0 is not allowed."
  }
}

variable "create_resource_group" {
  type        = bool
  default     = true
  description = "Whether to create a new Resource Group. Set false to reuse an existing one."
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Name of an existing Resource Group (only used when create_resource_group = false)."
}

variable "extra_public_ports" {
  type        = list(number)
  default     = []
  description = "Extra TCP ports allowed from my_ip on the public NSG (e.g. [80, 443, 8080])."
}
