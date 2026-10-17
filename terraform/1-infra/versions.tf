terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Local state keeps the lab simple. For teams, use the S3 backend (see docs/01-terraform-explained.md).
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project    = var.cluster_name
      managed_by = "terraform"
    }
  }
}
