#!/usr/bin/env bash
set -euo pipefail

PR_NUMBER="${1:?Usage: preview-cleanup.sh <pr-number>}"
APP_NAME="flux-preview-${PR_NUMBER}"

echo "==> Destroying preview app ${APP_NAME}..."
fly apps destroy "${APP_NAME}" -y

echo "==> Done."
