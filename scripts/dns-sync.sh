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

PRUNE=false
if [[ "${1:-}" == "--prune" ]]; then
  PRUNE=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Exporting desired DNS records from CUE..."
DESIRED=$(cd "$REPO_ROOT" && cue export ./dns --out json)
DOMAIN=$(echo "$DESIRED" | jq -r '.domain')
DESIRED_RECORDS=$(echo "$DESIRED" | jq -c '.records')

echo "==> Fetching current DNS records from Porkbun for ${DOMAIN}..."
CURRENT=$(curl -s -X POST "https://api.porkbun.com/api/json/v3/dns/retrieve/${DOMAIN}" \
  -H "Content-Type: application/json" \
  -d "{\"apikey\":\"${PORKBUN_API_KEY}\",\"secretapikey\":\"${PORKBUN_SECRET_KEY}\"}")

if [[ "$(echo "$CURRENT" | jq -r '.status')" != "SUCCESS" ]]; then
  echo "Error: Failed to retrieve DNS records: $(echo "$CURRENT" | jq -r '.message')" >&2
  exit 1
fi

CURRENT_RECORDS=$(echo "$CURRENT" | jq -c '.records // []')

DESIRED_COUNT=$(echo "$DESIRED_RECORDS" | jq 'length')
CREATED=0
UPDATED=0
DELETED=0
UNCHANGED=0

for i in $(seq 0 $((DESIRED_COUNT - 1))); do
  RECORD=$(echo "$DESIRED_RECORDS" | jq -c ".[$i]")
  TYPE=$(echo "$RECORD" | jq -r '.type')
  NAME=$(echo "$RECORD" | jq -r '.name')
  CONTENT=$(echo "$RECORD" | jq -r '.content')
  TTL=$(echo "$RECORD" | jq -r '.ttl')

  # Porkbun stores the FQDN; our CUE has just the subdomain
  FQDN="${NAME}.${DOMAIN}"

  # Find matching current record by type and FQDN
  MATCH=$(echo "$CURRENT_RECORDS" | jq -c "[.[] | select(.type == \"${TYPE}\" and .name == \"${FQDN}\")] | .[0] // empty")

  if [[ -z "$MATCH" || "$MATCH" == "null" ]]; then
    echo "  Creating ${TYPE} ${FQDN} -> ${CONTENT} (TTL ${TTL})"
    RESULT=$(curl -s -X POST "https://api.porkbun.com/api/json/v3/dns/create/${DOMAIN}" \
      -H "Content-Type: application/json" \
      -d "{\"apikey\":\"${PORKBUN_API_KEY}\",\"secretapikey\":\"${PORKBUN_SECRET_KEY}\",\"type\":\"${TYPE}\",\"name\":\"${NAME}\",\"content\":\"${CONTENT}\",\"ttl\":\"${TTL}\"}")
    if [[ "$(echo "$RESULT" | jq -r '.status')" != "SUCCESS" ]]; then
      echo "  Error creating record: $(echo "$RESULT" | jq -r '.message')" >&2
      exit 1
    fi
    CREATED=$((CREATED + 1))
  else
    CURRENT_CONTENT=$(echo "$MATCH" | jq -r '.content')
    CURRENT_TTL=$(echo "$MATCH" | jq -r '.ttl')

    if [[ "$CURRENT_CONTENT" != "$CONTENT" || "$CURRENT_TTL" != "$TTL" ]]; then
      echo "  Updating ${TYPE} ${FQDN} -> ${CONTENT} (TTL ${TTL})"
      RESULT=$(curl -s -X POST "https://api.porkbun.com/api/json/v3/dns/editByNameType/${DOMAIN}/${TYPE}/${NAME}" \
        -H "Content-Type: application/json" \
        -d "{\"apikey\":\"${PORKBUN_API_KEY}\",\"secretapikey\":\"${PORKBUN_SECRET_KEY}\",\"content\":\"${CONTENT}\",\"ttl\":\"${TTL}\"}")
      if [[ "$(echo "$RESULT" | jq -r '.status')" != "SUCCESS" ]]; then
        echo "  Error updating record: $(echo "$RESULT" | jq -r '.message')" >&2
        exit 1
      fi
      UPDATED=$((UPDATED + 1))
    else
      UNCHANGED=$((UNCHANGED + 1))
    fi
  fi
done

if [[ "$PRUNE" == "true" ]]; then
  echo "==> Pruning records not in CUE definition..."
  CURRENT_COUNT=$(echo "$CURRENT_RECORDS" | jq 'length')
  for i in $(seq 0 $((CURRENT_COUNT - 1))); do
    RECORD=$(echo "$CURRENT_RECORDS" | jq -c ".[$i]")
    TYPE=$(echo "$RECORD" | jq -r '.type')
    FQDN=$(echo "$RECORD" | jq -r '.name')

    # Skip records managed outside CUE (NS, SOA, etc.)
    if [[ "$TYPE" == "NS" || "$TYPE" == "SOA" ]]; then
      continue
    fi

    # Skip records for the bare domain (no subdomain)
    if [[ "$FQDN" == "$DOMAIN" ]]; then
      continue
    fi

    # Extract subdomain from FQDN
    SUBDOMAIN="${FQDN%.${DOMAIN}}"

    # Skip preview records — they're managed by dns-preview.sh
    if [[ "$SUBDOMAIN" == preview-* ]]; then
      continue
    fi

    # Check if this record exists in desired state
    MATCH=$(echo "$DESIRED_RECORDS" | jq -c "[.[] | select(.type == \"${TYPE}\" and .name == \"${SUBDOMAIN}\")] | .[0] // empty")
    if [[ -z "$MATCH" || "$MATCH" == "null" ]]; then
      RECORD_ID=$(echo "$RECORD" | jq -r '.id')
      echo "  Deleting ${TYPE} ${FQDN} (id: ${RECORD_ID})"
      RESULT=$(curl -s -X POST "https://api.porkbun.com/api/json/v3/dns/delete/${DOMAIN}/${RECORD_ID}" \
        -H "Content-Type: application/json" \
        -d "{\"apikey\":\"${PORKBUN_API_KEY}\",\"secretapikey\":\"${PORKBUN_SECRET_KEY}\"}")
      if [[ "$(echo "$RESULT" | jq -r '.status')" != "SUCCESS" ]]; then
        echo "  Error deleting record: $(echo "$RESULT" | jq -r '.message')" >&2
        exit 1
      fi
      DELETED=$((DELETED + 1))
    fi
  done
fi

echo "==> Done: ${CREATED} created, ${UPDATED} updated, ${DELETED} deleted, ${UNCHANGED} unchanged"
