#!/usr/bin/env bash
# Destroy everything: the app layer FIRST (so Kubernetes deletes the load balancer),
# then the infrastructure layer.
source "$(dirname "$0")/config.sh"

step "Destroying the app layer (namespace, deployment, service → NLB)"
terraform -chdir="$APP_DIR" destroy "$@"

step "Destroying the infra layer (cluster, nodes, VPC, ECR) ~10-15 minutes"
terraform -chdir="$INFRA_DIR" destroy "$@"
echo "✅ All lab resources destroyed."
