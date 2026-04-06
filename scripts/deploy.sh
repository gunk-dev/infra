#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${FLY_API_TOKEN:-}" ]]; then
  echo "Error: FLY_API_TOKEN is not set" >&2
  exit 1
fi

APP_TYPE="${1:?Usage: deploy.sh <app> <preview|staging|prod> [pr-number] [image]}"
ENV="${2:?Usage: deploy.sh <app> <preview|staging|prod> [pr-number] [image]}"
PR_NUMBER="${3:-}"
IMAGE="${4:-}"

case "$APP_TYPE" in
  flux|balance|web) ;;
  *)
    echo "Error: app must be flux, balance, or web" >&2
    exit 1
    ;;
esac

# Map app type to Fly app name prefix (web -> gunk-web, others unchanged)
case "$APP_TYPE" in
  web) APP_PREFIX="gunk-web" ;;
  *)   APP_PREFIX="$APP_TYPE" ;;
esac

case "$ENV" in
  preview)
    if [[ -z "$PR_NUMBER" ]]; then
      echo "Error: PR number required for preview deployments" >&2
      exit 1
    fi
    APP_NAME="${APP_PREFIX}-preview-${PR_NUMBER}"
    CUE_TAG="preview"
    ;;
  staging)
    APP_NAME="${APP_PREFIX}-staging"
    CUE_TAG="staging"
    ;;
  prod)
    APP_NAME="${APP_PREFIX}-prod"
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
  cue export "./apps/${APP_TYPE}" -t preview -t "appName=${APP_NAME}" -e preview \
    --out toml --outfile "${TMPDIR}/fly.toml"
else
  cue export "./apps/${APP_TYPE}" -t "${CUE_TAG}" -e "${CUE_TAG}" \
    --out toml --outfile "${TMPDIR}/fly.toml"
fi

echo "==> Ensuring app ${APP_NAME} exists in org gunk-dev..."
if ! fly apps list --org gunk-dev | grep -q "^${APP_NAME}"; then
  fly apps create "${APP_NAME}" --org gunk-dev
fi

if [[ "$APP_TYPE" == "flux" ]]; then
  echo "==> Building OCI image..."
  nix build .#oci-image
  IMAGE_PATH="$(readlink -f result)"

  echo "==> Deploying ${APP_NAME}..."
  fly deploy \
    --config "${TMPDIR}/fly.toml" \
    --app "${APP_NAME}" \
    --local-only \
    --image-label "latest" \
    --docker-image "file://${IMAGE_PATH}"
else
  if [[ -z "$IMAGE" ]]; then
    echo "Error: image argument required for ${APP_TYPE} deployments" >&2
    echo "Usage: deploy.sh ${APP_TYPE} ${ENV} [pr-number] <image>" >&2
    exit 1
  fi

  echo "==> Deploying ${APP_NAME} with image ${IMAGE}..."
  fly deploy \
    --config "${TMPDIR}/fly.toml" \
    --app "${APP_NAME}" \
    --image "${IMAGE}"
fi

echo "==> Configuring custom domains..."
if [[ "$ENV" == "preview" ]]; then
  DOMAIN="preview-${PR_NUMBER}.${APP_TYPE}.gunk.dev"
  echo "Configuring certificate for $DOMAIN"
  fly certs create "$DOMAIN" -a "${APP_NAME}" || true
else
  DOMAINS=$(cue export "./apps/${APP_TYPE}" -t "${CUE_TAG}" -e "${CUE_TAG}" --out json | jq -r '.custom_domains[]? // empty')
  for domain in $DOMAINS; do
    echo "Configuring certificate for $domain"
    fly certs create "$domain" -a "${APP_NAME}" || true
  done
fi

echo "==> Deployed: https://${APP_NAME}.fly.dev"
