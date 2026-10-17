#!/usr/bin/env bash
# Step 3 (and every release): deploy the website to EKS with Terraform.
#   ./scripts/03-deploy-app.sh v1
#   ./scripts/03-deploy-app.sh v2      # rolling update to a new image
source "$(dirname "$0")/config.sh"
TAG="${1:?usage: $0 <image-tag>}"; shift

terraform -chdir="$APP_DIR" init -input=false
terraform -chdir="$APP_DIR" apply -var "image_tag=${TAG}" "$@"

echo ""
echo "✅ $(terraform -chdir="$APP_DIR" output -raw website_url)"
echo "   (a new load balancer's DNS name can take 1-3 minutes to start resolving)"
