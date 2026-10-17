terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
  }
}

# Read the cluster name, region and ECR URL from the infra layer's state file.
# Two separate layers means the Kubernetes provider is only configured once the
# cluster already exists, which avoids a classic Terraform chicken-and-egg problem.
data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "${path.module}/../1-infra/terraform.tfstate"
  }
}

locals {
  cluster_name = data.terraform_remote_state.infra.outputs.cluster_name
  region       = data.terraform_remote_state.infra.outputs.region
  ecr_url      = data.terraform_remote_state.infra.outputs.ecr_repository_url
}

provider "aws" {
  region = local.region
}

data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

# Short-lived token for the IAM identity running Terraform (same as `aws eks get-token`)
data "aws_eks_cluster_auth" "this" {
  name = local.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
