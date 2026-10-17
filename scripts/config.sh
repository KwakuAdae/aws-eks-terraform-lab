#!/usr/bin/env bash
# Shared helpers for the lab scripts.
set -euo pipefail
export AWS_PAGER=""
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${ROOT_DIR}/terraform/1-infra"
APP_DIR="${ROOT_DIR}/terraform/2-app"
infra_out() { terraform -chdir="$INFRA_DIR" output -raw "$1"; }
step() { echo ""; echo "▶ $*"; }
