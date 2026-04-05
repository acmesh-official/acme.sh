#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
#
# acme.sh deploy hook: BytePlus Application Load Balancer (ALB)
# https://github.com/acmesh-official/acme.sh/wiki/deployhooks
#
# Deploys SSL/TLS certificates issued by acme.sh to BytePlus ALB.
# Supports automatic renewal with zero-downtime certificate rotation.
#
# ┌─────────────────────────────────────────────────────────────────────┐
# │  FIRST TIME (new domain)                                           │
# │  1. acme.sh --issue  -d example.com -w /var/www/html/              │
# │  2. acme.sh --deploy -d example.com --deploy-hook byteplus_alb     │
# │     → UploadCertificate → saves CertificateId                      │
# │  3. Manually assign cert to ALB Listener (one-time only)           │
# │                                                                    │
# │  RENEWAL (fully automatic)                                         │
# │  acme.sh cron triggers renew → deploy hook runs automatically      │
# │  → ReplaceCertificate (UpdateMode=new) — single API call           │
# │  → All attached listeners updated, old cert auto-deleted           │
# └─────────────────────────────────────────────────────────────────────┘
#
# Required environment variables:
#   export BYTEPLUS_ACCESS_KEY="AKAPxxxxxxxxxx"
#   export BYTEPLUS_SECRET_KEY="your-secret-key"
#
# Optional environment variables:
#   export BYTEPLUS_REGION="ap-southeast-3"            # default: ap-southeast-3
#   export BYTEPLUS_HOST="alb.ap-southeast-3.byteplusapi.com"  # custom API host
#   export BYTEPLUS_PROJECT_NAME="live"                 # default: "default" project
#   export BYTEPLUS_CERT_NAME=""                        # default: acme-{domain}-{YYYYMMDD-HHMM}
#   export BYTEPLUS_CERT_DESCRIPTION=""                 # default: empty
#   export BYTEPLUS_DELETE_OLD_CERT="true"              # default: true — auto-delete after replace
#
# API notes:
#   - All BytePlus ALB APIs use GET with query string parameters
#   - Request signing: HMAC-SHA256 with signed headers host;x-date
#   - PublicKey/PrivateKey are URL-encoded (RFC 3986) in query string
#   - ReplaceCertificate with UpdateMode=new uploads + replaces in 1 call
#
# Dependencies: curl, openssl, awk (standard on most Linux)
#
# Docs:
#   Signing — https://docs.byteplus.com/en/docs/byteplus-platform/reference-how-to-calculate-a-signature
#   ALB API — https://docs.byteplus.com/en/docs/byteplus-alb

# ══════════════════════════════════════════════════════════════════════════════
#  Constants
# ══════════════════════════════════════════════════════════════════════════════

# SHA-256 hash of empty string (used for GET requests with no body)
_BYTEPLUS_EMPTY_HASH="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# ══════════════════════════════════════════════════════════════════════════════
#  Main deploy function — called by acme.sh
# ══════════════════════════════════════════════════════════════════════════════

byteplus_alb_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  # ── 1. Load & validate credentials ──────────────────────────────────────────

  # Preserve environment values before _getdeployconf (which may reset them)
  _env_project_name="${BYTEPLUS_PROJECT_NAME:-}"
  _env_delete_old="${BYTEPLUS_DELETE_OLD_CERT:-}"

  _getdeployconf BYTEPLUS_ACCESS_KEY
  _getdeployconf BYTEPLUS_SECRET_KEY
  _getdeployconf BYTEPLUS_REGION
  _getdeployconf BYTEPLUS_HOST
  _getdeployconf BYTEPLUS_PROJECT_NAME
  _getdeployconf BYTEPLUS_DELETE_OLD_CERT
  _getdeployconf BYTEPLUS_CERT_NAME
  _getdeployconf BYTEPLUS_CERT_DESCRIPTION

  # Restore from environment if _getdeployconf cleared them
  if [ -z "$BYTEPLUS_PROJECT_NAME" ] && [ -n "$_env_project_name" ]; then
    _debug "Restoring BYTEPLUS_PROJECT_NAME from environment"
    BYTEPLUS_PROJECT_NAME="$_env_project_name"
  fi
  if [ -z "$BYTEPLUS_DELETE_OLD_CERT" ] && [ -n "$_env_delete_old" ]; then
    BYTEPLUS_DELETE_OLD_CERT="$_env_delete_old"
  fi

  # Validate required credentials
  if [ -z "$BYTEPLUS_ACCESS_KEY" ]; then
    _err "BYTEPLUS_ACCESS_KEY is not set."
    _err "Please run: export BYTEPLUS_ACCESS_KEY=\"your-access-key\""
    return 1
  fi
  if [ -z "$BYTEPLUS_SECRET_KEY" ]; then
    _err "BYTEPLUS_SECRET_KEY is not set."
    _err "Please run: export BYTEPLUS_SECRET_KEY=\"your-secret-key\""
    return 1
  fi

  # Save credentials for future runs
  _savedeployconf BYTEPLUS_ACCESS_KEY "$BYTEPLUS_ACCESS_KEY"
  _savedeployconf BYTEPLUS_SECRET_KEY "$BYTEPLUS_SECRET_KEY"

  # Region (default: ap-southeast-3)
  BYTEPLUS_REGION="${BYTEPLUS_REGION:-ap-southeast-3}"
  _savedeployconf BYTEPLUS_REGION "$BYTEPLUS_REGION"

  # Project name
  if [ -n "$BYTEPLUS_PROJECT_NAME" ]; then
    _savedeployconf BYTEPLUS_PROJECT_NAME "$BYTEPLUS_PROJECT_NAME"
    _info "Using project: $BYTEPLUS_PROJECT_NAME"
  else
    _info "WARNING: BYTEPLUS_PROJECT_NAME is not set. Cert will go to 'default' project."
  fi

  # Delete old cert toggle (default: true)
  BYTEPLUS_DELETE_OLD_CERT="${BYTEPLUS_DELETE_OLD_CERT:-true}"
  _savedeployconf BYTEPLUS_DELETE_OLD_CERT "$BYTEPLUS_DELETE_OLD_CERT"

  # API host — custom override or auto-build from region
  if [ -n "$BYTEPLUS_HOST" ]; then
    _BYTEPLUS_HOST="$BYTEPLUS_HOST"
    _savedeployconf BYTEPLUS_HOST "$BYTEPLUS_HOST"
  else
    _BYTEPLUS_HOST="alb.${BYTEPLUS_REGION}.byteplusapi.com"
  fi
  _info "Using API host: $_BYTEPLUS_HOST"
  _BYTEPLUS_SERVICE="alb"

  # ── 2. Build certificate name ────────────────────────────────────────────────

  _date_tag=$(date -u +%Y%m%d-%H%M)
  # Replace wildcard * and dots for a valid cert name
  _safe_domain=$(echo "$_cdomain" | sed 's/\*\.//g' | sed 's/\./-/g')
  # Safe identifier version for deployconf keys: map all non [A-Za-z0-9_] to _
  _conf_key=$(echo "$_cdomain" | sed 's/^\*\.//' | sed 's/[^A-Za-z0-9_]/_/g')

  if [ -z "$BYTEPLUS_CERT_NAME" ]; then
    BYTEPLUS_CERT_NAME="acme-${_safe_domain}-${_date_tag}"
  fi

  # Enforce BytePlus naming rules: start with letter, max 128 chars
  BYTEPLUS_CERT_NAME=$(echo "$BYTEPLUS_CERT_NAME" | sed 's/[^a-zA-Z0-9._-]/-/g' | cut -c1-128)

  _info "Certificate name: $BYTEPLUS_CERT_NAME"

  # ── 3. Read cert and key ─────────────────────────────────────────────────────
  # BytePlus requires NO blank lines between PEM blocks in the certificate chain

  _public_key=$(sed '/^[[:space:]]*$/d' "$_cfullchain" | tr -d '\r')
  _private_key=$(sed '/^[[:space:]]*$/d' "$_ckey" | tr -d '\r')

  if [ -z "$_public_key" ] || [ -z "$_private_key" ]; then
    _err "Failed to read certificate or key file."
    return 1
  fi

  # ── 4. Deploy: first-time upload or renewal replace ─────────────────────────

  _getdeployconf "BYTEPLUS_CERT_ID_${_conf_key}"
  _old_cert_id=$(eval echo "\$BYTEPLUS_CERT_ID_${_conf_key}")

  if [ -z "$_old_cert_id" ]; then
    _byteplus_first_time_deploy
  else
    _byteplus_renewal_deploy
  fi

  # Check if deploy step set _new_cert_id
  if [ -z "$_new_cert_id" ]; then
    return 1
  fi

  # ── 5. Save new CertificateId for next renewal ───────────────────────────────

  _savedeployconf "BYTEPLUS_CERT_ID_${_conf_key}" "$_new_cert_id"
  _info "Saved CertificateId '$_new_cert_id' for domain '$_cdomain'."

  return 0
}

# ══════════════════════════════════════════════════════════════════════════════
#  Deploy: First time — UploadCertificate
# ══════════════════════════════════════════════════════════════════════════════

_byteplus_first_time_deploy() {
  _info "No previous CertificateId found."
  _err "Refusing to upload certificate material because this hook passes PublicKey/PrivateKey as request parameters."
  _err "Uploading a private key in the request URL can leak it via logs, proxies, and process listings."
  _err "Please upload the certificate to BytePlus manually for the initial deployment, set BYTEPLUS_CERT_ID, and rerun."
  _err "This hook must be updated to send PublicKey and PrivateKey in a POST body before automatic first-time upload can be enabled safely."
  return 1
}

# ══════════════════════════════════════════════════════════════════════════════
#  Deploy: Renewal — ReplaceCertificate (UpdateMode=new)
# ══════════════════════════════════════════════════════════════════════════════

_byteplus_renewal_deploy() {
  _info "Replacing old certificate '$_old_cert_id' (UpdateMode=new)..."

  if [ -n "$BYTEPLUS_PROJECT_NAME" ]; then
    _replace_response=$(_byteplus_alb_api "ReplaceCertificate" \
      "OldCertificateId=${_old_cert_id}" \
      "UpdateMode=new" \
      "CertificateName=${BYTEPLUS_CERT_NAME}" \
      "ProjectName=${BYTEPLUS_PROJECT_NAME}" \
      "PublicKey=${_public_key}" \
      "PrivateKey=${_private_key}")
  else
    _replace_response=$(_byteplus_alb_api "ReplaceCertificate" \
      "OldCertificateId=${_old_cert_id}" \
      "UpdateMode=new" \
      "CertificateName=${BYTEPLUS_CERT_NAME}" \
      "PublicKey=${_public_key}" \
      "PrivateKey=${_private_key}")
  fi

  _debug2 _replace_response "$_replace_response"

  _new_cert_id=$(_byteplus_extract_cert_id "$_replace_response")

  if [ -z "$_new_cert_id" ]; then
    _err "ReplaceCertificate failed: $(_byteplus_extract_error "$_replace_response")"
    _debug2 "Full response" "$_replace_response"
    return 1
  fi

  _info "Certificate replaced successfully on all attached listeners."
  _info "New CertificateId: $_new_cert_id"

  # Auto-cleanup old certificate
  if [ "$BYTEPLUS_DELETE_OLD_CERT" = "true" ]; then
    _byteplus_delete_old_cert "$_old_cert_id"
  else
    _info "Auto-delete disabled. Old certificate '$_old_cert_id' kept in inventory."
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  Delete old certificate (with retry)
# ══════════════════════════════════════════════════════════════════════════════

_byteplus_delete_old_cert() {
  _del_cert_id="$1"

  _info "Waiting 5s for cert status to settle..."
  sleep 5

  _info "Deleting old certificate '$_del_cert_id'..."
  _del_response=$(_byteplus_alb_api "DeleteCertificate" "CertificateId=${_del_cert_id}")

  if echo "$_del_response" | grep -q '"Error"'; then
    _info "Delete failed, retrying in 10s..."
    sleep 10
    _del_response=$(_byteplus_alb_api "DeleteCertificate" "CertificateId=${_del_cert_id}")

    if echo "$_del_response" | grep -q '"Error"'; then
      _info "Warning: Could not delete old certificate '$_del_cert_id'."
      _info "Error: $(_byteplus_extract_error "$_del_response")"
      _info "Please remove it manually from BytePlus Console."
    else
      _info "Old certificate '$_del_cert_id' deleted (retry succeeded)."
    fi
  else
    _info "Old certificate '$_del_cert_id' deleted."
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  JSON response helpers
# ══════════════════════════════════════════════════════════════════════════════

# Extract CertificateId from API response JSON
_byteplus_extract_cert_id() {
  echo "$1" | _egrep_o '"CertificateId"\s*:\s*"[^"]*"' | head -1 | _egrep_o '"[^"]*"$' | tr -d '"'
}

# Extract error message from API response JSON
_byteplus_extract_error() {
  _code=$(echo "$1" | _egrep_o '"Code"\s*:\s*"[^"]*"' | head -1 | _egrep_o '"[^"]*"$' | tr -d '"')
  _msg=$(echo "$1" | _egrep_o '"Message"\s*:\s*"[^"]*"' | head -1 | _egrep_o '"[^"]*"$' | tr -d '"')
  if [ -n "$_code" ]; then
    printf '%s — %s' "$_code" "$_msg"
  else
    printf '%s' "$1"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  BytePlus ALB API caller
# ══════════════════════════════════════════════════════════════════════════════

# Usage: _byteplus_alb_api ACTION [param1=val1] [param2=val2] ...
# All parameters sent via GET query string. Signing: HMAC-SHA256, host;x-date.
_byteplus_alb_api() {
  _action="$1"
  shift

  # Build query string — all params go in URL
  _query_params="Action=${_action}&Version=2020-04-01"

  for _param in "$@"; do
    _pname="${_param%%=*}"
    _pval="${_param#*=}"
    _query_params="${_query_params}&${_pname}=$(_byteplus_urlencode "$_pval")"
  done

  # Timestamps
  _x_date=$(date -u +%Y%m%dT%H%M%SZ)
  _date_only=$(date -u +%Y%m%d)

  # Sort query params for canonical request
  _sorted_query=$(echo "$_query_params" | tr '&' '\n' | sort | tr '\n' '&' | sed 's/&$//')

  # Canonical headers — only host and x-date
  _canonical_headers="host:${_BYTEPLUS_HOST}
x-date:${_x_date}
"
  _signed_headers="host;x-date"

  # Canonical request
  _canonical_request="GET
/
${_sorted_query}
${_canonical_headers}
${_signed_headers}
${_BYTEPLUS_EMPTY_HASH}"

  _debug2 _canonical_request "$_canonical_request"

  # Hash of canonical request
  _cr_hash=$(printf '%s' "$_canonical_request" | openssl dgst -sha256 | awk '{print $NF}')

  # Credential scope
  _credential_scope="${_date_only}/${BYTEPLUS_REGION}/${_BYTEPLUS_SERVICE}/request"

  # String to sign
  _string_to_sign="HMAC-SHA256
${_x_date}
${_credential_scope}
${_cr_hash}"

  _debug2 _string_to_sign "$_string_to_sign"

  # Signing key derivation (HMAC chain)
  _k_date=$(printf '%s' "$_date_only" | openssl dgst -sha256 -hmac "$BYTEPLUS_SECRET_KEY" | awk '{print $NF}')
  _k_region=$(printf '%s' "$BYTEPLUS_REGION" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${_k_date}" | awk '{print $NF}')
  _k_service=$(printf '%s' "$_BYTEPLUS_SERVICE" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${_k_region}" | awk '{print $NF}')
  _k_signing=$(printf '%s' "request" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${_k_service}" | awk '{print $NF}')

  # Final signature
  _signature=$(printf '%s' "$_string_to_sign" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${_k_signing}" | awk '{print $NF}')

  # Authorization header
  _auth="HMAC-SHA256 Credential=${BYTEPLUS_ACCESS_KEY}/${_credential_scope}, SignedHeaders=${_signed_headers}, Signature=${_signature}"

  _debug2 _auth "$_auth"

  # Build URL and execute GET request
  _url="https://${_BYTEPLUS_HOST}/?${_sorted_query}"

  _response=$(curl -s --connect-timeout 10 --max-time 60 -X GET \
    -H "Authorization: ${_auth}" \
    -H "X-Date: ${_x_date}" \
    -H "Host: ${_BYTEPLUS_HOST}" \
    "${_url}")

  _debug2 "_byteplus_alb_api response [$_action]" "$_response"
  printf '%s' "$_response"
}

# ══════════════════════════════════════════════════════════════════════════════
#  URL encode (RFC 3986) — awk-based for performance
# ══════════════════════════════════════════════════════════════════════════════

_byteplus_urlencode() {
  printf '%s' "$1" | awk 'BEGIN {
    for (i = 0; i <= 255; i++) {
      c = sprintf("%c", i)
      if (c ~ /[a-zA-Z0-9.~_\-]/)
        safe[i] = c
      else
        safe[i] = sprintf("%%%02X", i)
    }
  }
  {
    n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      printf "%s", safe[ord(c)]
    }
    # Print newline as %0A (except trailing, which command substitution strips)
    if (NR > 0) printf "%%0A"
  }
  function ord(c,   i2) {
    for (i2 = 0; i2 <= 255; i2++)
      if (sprintf("%c", i2) == c) return i2
    return 0
  }
  END { }' | sed 's/%0A$//'
}
