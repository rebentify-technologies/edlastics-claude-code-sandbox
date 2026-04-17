#!/bin/bash
# Provides _gcp_refresh_token (exports GCP_ARTIFACT_REGISTRY_AUTH_TOKEN) and
# an npm wrapper that auto-retries on GCP AR auth failures.
#
# Uses google-auth-library (installed globally in the Dockerfile) to exchange
# the service account key for a short-lived OAuth2 access token.

_gcp_refresh_token() {
  if [ -z "${GCP_SERVICE_ACCOUNT_KEY_BASE64:-}" ]; then
    echo "gcp-auth: GCP_SERVICE_ACCOUNT_KEY_BASE64 not set — skipping" >&2
    return 0
  fi

  local token
  token=$(NODE_PATH=/usr/local/share/npm-global/lib/node_modules node -e "
    const {GoogleAuth} = require('google-auth-library');
    const creds = JSON.parse(Buffer.from(process.env.GCP_SERVICE_ACCOUNT_KEY_BASE64, 'base64'));
    new GoogleAuth({credentials: creds, scopes: ['https://www.googleapis.com/auth/cloud-platform']})
      .getAccessToken().then(t => console.log(t)).catch(e => { console.error(e.message); process.exit(1); });
  ") || return 1

  if [ -z "$token" ]; then
    echo "gcp-auth: failed to obtain access token" >&2
    return 1
  fi

  export GCP_ARTIFACT_REGISTRY_AUTH_TOKEN="$token"
  export GCP_TOKEN_EXPIRES_AT=$(($(date +%s) + 3600))
  echo "gcp-auth: GCP_ARTIFACT_REGISTRY_AUTH_TOKEN refreshed (valid 1h)" >&2
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
