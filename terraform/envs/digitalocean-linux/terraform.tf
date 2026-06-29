terraform {
  required_version = ">= 1.9"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.92"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}
