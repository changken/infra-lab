terraform {
  required_version = ">= 1.9.0"

  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.33.2"
    }
  }
}
