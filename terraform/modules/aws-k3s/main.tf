terraform {
  cloud {
    organization = "changkenkai"
    workspaces {
      name = "my-k3s-aws-lab"
    }
  }

  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Credentials automatically loaded from:
  # - AWS CLI (aws configure)
  # - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
}
