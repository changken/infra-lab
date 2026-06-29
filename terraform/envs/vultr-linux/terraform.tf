terraform {
  required_version = ">= 1.9"
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.31"
    }
  }
}

provider "vultr" {
  api_key     = var.api_key
  rate_limit  = 100
  retry_limit = 3
}
