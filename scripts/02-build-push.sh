#!/usr/bin/env bash
# Step 2: Build the website image and push it to the ECR repository Terraform created.
#   ./scripts/02-build-push.sh v1
source "$(dirname "$0")/config.sh"
TAG="${1:?usage: $0 <image-tag, e.g. v1>}"
REPO="$(infra_out ecr_repository_url)"
REGION="$(infra_out region)"

step "Logging Docker in to ECR"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${REPO%%/*}"

step "Building and pushing ${REPO}:${TAG}"
docker build --platform linux/amd64 -t "${REPO}:${TAG}" "${ROOT_DIR}/app"
docker push "${REPO}:${TAG}"
