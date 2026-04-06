#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${FLY_API_TOKEN:-}" ]]; then
  echo "Error: FLY_API_TOKEN is not set" >&2
  exit 1
fi

ENV="${1:?Usage: deploy.sh <preview|staging|prod> [pr-number]}"
PR_NUMBER="${2:-}"

case "$ENV" in
  preview)
    if [[ -z "$PR_NUMBER" ]]; then
      echo "Error: PR number required for preview deployments" >&2
      exit 1
    fi
    APP_NAME="flux-preview-${PR_NUMBER}"
    CUE_TAG="preview"
    ;;
  staging)
    APP_NAME="flux-staging"
    CUE_TAG="staging"
    ;;
  prod)
    APP_NAME="flux-prod"
    CUE_TAG="prod"
    ;;
  *)
    echo "Error: environment must be preview, staging, or prod" >&2
    exit 1
    ;;
esac

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "==> Generating fly.toml for ${APP_NAME}..."
if [[ "$ENV" == "preview" ]]; then
  cue export ./apps/flux -t preview -t "appName=${APP_NAME}" -e preview \
    --out toml --outfile "${TMPDIR}/fly.toml"
else
  cue export ./apps/flux -t "${CUE_TAG}" -e "${CUE_TAG}" \
    --out toml --outfile "${TMPDIR}/fly.toml"
fi

echo "==> Building OCI image..."
nix build .#oci-image
IMAGE_PATH="$(readlink -f result)"

echo "==> Ensuring app ${APP_NAME} exists in org gunk-dev..."
if ! fly apps list --org gunk-dev | grep -q "^${APP_NAME}"; then
  fly apps create "${APP_NAME}" --org gunk-dev
fi

echo "==> Deploying ${APP_NAME}..."
fly deploy \
  --config "${TMPDIR}/fly.toml" \
  --app "${APP_NAME}" \
  --local-only \
  --image-label "latest" \
  --docker-image "file://${IMAGE_PATH}"

echo "==> Deployed: https://${APP_NAME}.fly.dev"
