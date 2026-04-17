#!/bin/bash
# Provides _gcp_refresh_token (exports GCP_ARTIFACT_REGISTRY_AUTH_TOKEN) and
# an npm wrapper that auto-retries on GCP AR auth failures.

_gcp_refresh_token() {
  if [ -z "${GCP_SERVICE_ACCOUNT_KEY_BASE64:-}" ]; then
    echo "gcp-auth: GCP_SERVICE_ACCOUNT_KEY_BASE64 not set — skipping" >&2
    return 0
  fi

  local tmpdir
  tmpdir=$(mktemp -d)
  chmod 700 "$tmpdir"

  local sa_email key_id now exp header claim signing_input signature jwt token
  local rc=0

  echo "$GCP_SERVICE_ACCOUNT_KEY_BASE64" | base64 -d > "$tmpdir/key.json" \
    && chmod 600 "$tmpdir/key.json" \
    && sa_email=$(jq -r .client_email "$tmpdir/key.json") \
    && key_id=$(jq -r .private_key_id "$tmpdir/key.json") \
    && jq -r .private_key "$tmpdir/key.json" > "$tmpdir/key.pem" \
    && chmod 600 "$tmpdir/key.pem" || rc=1

  if [ $rc -eq 0 ]; then
    now=$(date +%s)
    exp=$((now + 3600))
    header=$(printf '{"alg":"RS256","typ":"JWT","kid":"%s"}' "$key_id" | base64 -w0 | tr '+/' '-_' | tr -d '=')
    claim=$(printf '{"iss":"%s","scope":"https://www.googleapis.com/auth/cloud-platform","aud":"https://oauth2.googleapis.com/token","exp":%d,"iat":%d}' "$sa_email" "$exp" "$now" | base64 -w0 | tr '+/' '-_' | tr -d '=')
    signing_input="${header}.${claim}"
    signature=$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$tmpdir/key.pem" -binary | base64 -w0 | tr '+/' '-_' | tr -d '=') \
      && jwt="${signing_input}.${signature}" \
      && token=$(curl -sf -X POST https://oauth2.googleapis.com/token \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt" | jq -r .access_token) || rc=1
  fi

  rm -rf "$tmpdir"

  if [ $rc -ne 0 ] || [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "gcp-auth: failed to obtain access token" >&2
    return 1
  fi

  export GCP_ARTIFACT_REGISTRY_AUTH_TOKEN="$token"
  export GCP_TOKEN_EXPIRES_AT="$exp"
  echo "gcp-auth: GCP_ARTIFACT_REGISTRY_AUTH_TOKEN refreshed (valid 1h, SA: $sa_email)" >&2
}

# Skip refresh if the current token is still valid (5 min safety margin).
if [ -z "${GCP_TOKEN_EXPIRES_AT:-}" ] || [ "$(date +%s)" -ge "$((GCP_TOKEN_EXPIRES_AT - 300))" ]; then
  _gcp_refresh_token
fi

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
    export _NPM_RETRY=1
    command npm "$@"
    local retry_code=$?
    unset _NPM_RETRY
    return $retry_code
  fi

  rm -f "$errfile"
  return $exit_code
}
