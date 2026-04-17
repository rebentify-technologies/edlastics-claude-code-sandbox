#!/bin/bash
# Exchanges a base64-encoded GCP service account key for a short-lived (1h)
# OAuth2 access token, exported as GCP_ARTIFACT_REGISTRY_AUTH_TOKEN for .npmrc.
#
# Also defines an npm wrapper that detects GCP AR auth failures and retries
# once after refreshing the token.
#
# Usage: source this script (idempotent).

_gcp_refresh_token() {
  if [ -z "${GCP_SERVICE_ACCOUNT_KEY_BASE64:-}" ]; then
    echo "gcp-auth: GCP_SERVICE_ACCOUNT_KEY_BASE64 not set — skipping" >&2
    return 0
  fi

  local tmpdir
  tmpdir=$(mktemp -d)

  echo "$GCP_SERVICE_ACCOUNT_KEY_BASE64" | base64 -d > "$tmpdir/key.json"

  local sa_email key_id
  sa_email=$(jq -r .client_email "$tmpdir/key.json")
  key_id=$(jq -r .private_key_id "$tmpdir/key.json")
  jq -r .private_key "$tmpdir/key.json" > "$tmpdir/key.pem"

  local now=$(date +%s)
  local exp=$((now + 3600))

  local header claim signing_input signature jwt
  header=$(printf '{"alg":"RS256","typ":"JWT","kid":"%s"}' "$key_id" | base64 -w0 | tr '+/' '-_' | tr -d '=')
  claim=$(printf '{"iss":"%s","scope":"https://www.googleapis.com/auth/cloud-platform","aud":"https://oauth2.googleapis.com/token","exp":%d,"iat":%d}' "$sa_email" "$exp" "$now" | base64 -w0 | tr '+/' '-_' | tr -d '=')
  signing_input="${header}.${claim}"
  signature=$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$tmpdir/key.pem" -binary | base64 -w0 | tr '+/' '-_' | tr -d '=')
  jwt="${signing_input}.${signature}"

  local token
  token=$(curl -s -X POST https://oauth2.googleapis.com/token \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt" | jq -r .access_token)

  rm -rf "$tmpdir"

  if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "gcp-auth: failed to obtain access token" >&2
    return 1
  fi

  export GCP_ARTIFACT_REGISTRY_AUTH_TOKEN="$token"
  echo "gcp-auth: GCP_ARTIFACT_REGISTRY_AUTH_TOKEN refreshed (valid 1h, SA: $sa_email)" >&2
}

_gcp_refresh_token

# Wrapper: retries npm once on GCP AR auth failure after refreshing the token.
# Preserves stdout (so `npm view version` etc. stay parseable); captures stderr
# to detect auth errors.
npm() {
  if [ -n "${_NPM_RETRY:-}" ] || [ -z "${GCP_SERVICE_ACCOUNT_KEY_BASE64:-}" ]; then
    command npm "$@"
    return $?
  fi

  local errfile
  errfile=$(mktemp)
  command npm "$@" 2> >(tee "$errfile" >&2)
  local exit_code=$?

  if [ $exit_code -ne 0 ] && grep -qE "E40[13]|403 Forbidden|401 Unauthorized|not have permission" "$errfile"; then
    rm -f "$errfile"
    echo "npm auth failed — refreshing GCP token and retrying..." >&2
    _gcp_refresh_token
    _NPM_RETRY=1 command npm "$@"
    return $?
  fi

  rm -f "$errfile"
  return $exit_code
}
