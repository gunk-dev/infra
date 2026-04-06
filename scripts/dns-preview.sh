#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${PORKBUN_API_KEY:-}" ]]; then
  echo "Error: PORKBUN_API_KEY is not set" >&2
  exit 1
fi

if [[ -z "${PORKBUN_SECRET_KEY:-}" ]]; then
  echo "Error: PORKBUN_SECRET_KEY is not set" >&2
  exit 1
fi

ACTION="${1:?Usage: dns-preview.sh <create|delete> <app> <pr-number>}"
APP="${2:?Usage: dns-preview.sh <create|delete> <app> <pr-number>}"
PR_NUMBER="${3:?Usage: dns-preview.sh <create|delete> <app> <pr-number>}"

DOMAIN="gunk.dev"
SUBDOMAIN="preview-${PR_NUMBER}.${APP}"
FLY_HOSTNAME="${APP}-preview-${PR_NUMBER}.fly.dev"

case "$ACTION" in
  create)
    echo "==> Creating CNAME ${SUBDOMAIN}.${DOMAIN} -> ${FLY_HOSTNAME}"
    RESULT=$(curl -s -X POST "https://api.porkbun.com/api/json/v3/dns/create/${DOMAIN}" \
      -H "Content-Type: application/json" \
      -d "{\"apikey\":\"${PORKBUN_API_KEY}\",\"secretapikey\":\"${PORKBUN_SECRET_KEY}\",\"type\":\"CNAME\",\"name\":\"${SUBDOMAIN}\",\"content\":\"${FLY_HOSTNAME}\",\"ttl\":\"600\"}")
    if [[ "$(echo "$RESULT" | jq -r '.status')" != "SUCCESS" ]]; then
      # Record may already exist — try updating instead
      echo "  Create failed, attempting update..."
      RESULT=$(curl -s -X POST "https://api.porkbun.com/api/json/v3/dns/editByNameType/${DOMAIN}/CNAME/${SUBDOMAIN}" \
        -H "Content-Type: application/json" \
        -d "{\"apikey\":\"${PORKBUN_API_KEY}\",\"secretapikey\":\"${PORKBUN_SECRET_KEY}\",\"content\":\"${FLY_HOSTNAME}\",\"ttl\":\"600\"}")
      if [[ "$(echo "$RESULT" | jq -r '.status')" != "SUCCESS" ]]; then
        echo "  Error: $(echo "$RESULT" | jq -r '.message')" >&2
        exit 1
      fi
    fi
    echo "==> Done: ${SUBDOMAIN}.${DOMAIN} -> ${FLY_HOSTNAME}"
    ;;
  delete)
    echo "==> Deleting CNAME ${SUBDOMAIN}.${DOMAIN}"
    RESULT=$(curl -s -X POST "https://api.porkbun.com/api/json/v3/dns/deleteByNameType/${DOMAIN}/CNAME/${SUBDOMAIN}" \
      -H "Content-Type: application/json" \
      -d "{\"apikey\":\"${PORKBUN_API_KEY}\",\"secretapikey\":\"${PORKBUN_SECRET_KEY}\"}")
    if [[ "$(echo "$RESULT" | jq -r '.status')" != "SUCCESS" ]]; then
      echo "  Warning: $(echo "$RESULT" | jq -r '.message')" >&2
      # Don't fail on delete — the record may already be gone
    fi
    echo "==> Done."
    ;;
  *)
    echo "Error: action must be create or delete" >&2
    exit 1
    ;;
esac
