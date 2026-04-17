#!/bin/bash
# Exchanges a base64-encoded GCP service account key for a short-lived (1h)
# OAuth2 access token that can be used as an npm _authToken for Artifact Registry.
#
# Usage: source this script, or run: eval $(gcp-auth)
# Exports: GCP_ARTIFACT_REGISTRY_AUTH_TOKEN

set -euo pipefail

if [ -z "${GCP_SERVICE_ACCOUNT_KEY_BASE64:-}" ]; then
  echo "gcp-auth: GCP_SERVICE_ACCOUNT_KEY_BASE64 is not set — skipping token refresh" >&2
  return 0 2>/dev/null || exit 0
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

KEY_FILE="$TMPDIR/key.json"
PEM_FILE="$TMPDIR/key.pem"

echo "$GCP_SERVICE_ACCOUNT_KEY_BASE64" | base64 -d > "$KEY_FILE"

SA_EMAIL=$(jq -r .client_email "$KEY_FILE")
KEY_ID=$(jq -r .private_key_id "$KEY_FILE")
jq -r .private_key "$KEY_FILE" > "$PEM_FILE"

NOW=$(date +%s)
EXP=$((NOW + 3600))

HEADER=$(printf '{"alg":"RS256","typ":"JWT","kid":"%s"}' "$KEY_ID" | base64 -w0 | tr '+/' '-_' | tr -d '=')
CLAIM=$(printf '{"iss":"%s","scope":"https://www.googleapis.com/auth/cloud-platform","aud":"https://oauth2.googleapis.com/token","exp":%d,"iat":%d}' "$SA_EMAIL" "$EXP" "$NOW" | base64 -w0 | tr '+/' '-_' | tr -d '=')

SIGNING_INPUT="${HEADER}.${CLAIM}"
SIGNATURE=$(printf '%s' "$SIGNING_INPUT" | openssl dgst -sha256 -sign "$PEM_FILE" -binary | base64 -w0 | tr '+/' '-_' | tr -d '=')
JWT="${SIGNING_INPUT}.${SIGNATURE}"

ACCESS_TOKEN=$(curl -s -X POST https://oauth2.googleapis.com/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$JWT" | jq -r .access_token)

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  echo "gcp-auth: failed to obtain access token" >&2
  return 1 2>/dev/null || exit 1
fi

export GCP_ARTIFACT_REGISTRY_AUTH_TOKEN="$ACCESS_TOKEN"
echo "gcp-auth: GCP_ARTIFACT_REGISTRY_AUTH_TOKEN refreshed (valid for 1h, SA: $SA_EMAIL)" >&2
