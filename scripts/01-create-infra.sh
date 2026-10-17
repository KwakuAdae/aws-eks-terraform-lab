#!/usr/bin/env bash
# Step 1: VPC, EKS cluster, node group, add-ons and ECR with Terraform (~15-20 minutes).
source "$(dirname "$0")/config.sh"

step "terraform init"
terraform -chdir="$INFRA_DIR" init -input=false

step "terraform apply (review the plan, then type yes)"
terraform -chdir="$INFRA_DIR" apply "$@"

step "Pointing kubectl at the new cluster"
aws eks update-kubeconfig --region "$(infra_out region)" --name "$(infra_out cluster_name)"
kubectl get nodes -o wide
