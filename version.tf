terraform {
  required_version = ">= 1.13"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.64.0"
    }
  }
}

provider "aws" {
  # Configuration options
  region = var.aws_region
}
