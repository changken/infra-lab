# ---------- Variables ----------
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "my_ip" {
  type        = string
  description = "Your IP in CIDR, e.g. 1.2.3.4/32"
}

variable "spot_max_price" {
  type    = string
  default = null
}
