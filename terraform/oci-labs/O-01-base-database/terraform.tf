terraform {
  required_version = ">= 1.9"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

# 認證沿用 ~/.oci/config 的 [DEFAULT] profile（API key）
provider "oci" {
  region = var.region
}
