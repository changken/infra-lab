terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.23.0" # aws_ecs_express_gateway_service 在 v6.23.0 引入
    }
  }
}

provider "aws" {
  region = var.region
}
