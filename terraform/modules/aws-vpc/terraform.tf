terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  cloud {

    organization = "changkenkai"

    workspaces {
      name = "aws-vpc-lab"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
