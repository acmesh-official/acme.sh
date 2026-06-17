#!/usr/bin/env sh
# shellcheck disable=SC2034,SC2154
#
# acme.sh deploy hook: BytePlus Application Load Balancer (ALB)
# https://github.com/acmesh-official/acme.sh/wiki/deployhooks
#
# Deploys SSL/TLS certificates issued by acme.sh to BytePlus ALB.
# Supports automatic renewal with zero-downtime certificate rotation
# for certificates that have already been uploaded and have a saved
# BytePlus CertificateId.
#
# ┌─────────────────────────────────────────────────────────────────────┐
# │  FIRST TIME (new domain)                                           │
# │  1. acme.sh --issue  -d example.com -w /var/www/html/              │
# │  2. Upload/import the certificate to BytePlus ALB manually         │
# │  3. Save/configure the existing CertificateId for this hook        │
# │  4. Manually assign cert to ALB Listener (one-time only)           │
# │                                                                    │
# │  RENEWAL (fully automatic after CertificateId is configured)       │
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
  BYTEPLUS_CERT_NAME=$(echo "$BYTEPLUS_CERT_NAME" | sed 's/[^A-Za-z0-9._-]/-/g')
  case "$BYTEPLUS_CERT_NAME" in
  [A-Za-z]*) ;;

  *)
    BYTEPLUS_CERT_NAME="a$BYTEPLUS_CERT_NAME"
    ;;
  esac
  BYTEPLUS_CERT_NAME=$(echo "$BYTEPLUS_CERT_NAME" | cut -c1-128)

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
  _err "Please upload the certificate to BytePlus manually for the initial deployment, set BYTEPLUS_CERT_ID_${_conf_key} to that CertificateId, and rerun."
  _err "This hook stores CertificateId values per domain using deployconf, so the variable name must include the current domain-specific suffix."
  _err "This hook must be updated to send PublicKey and PrivateKey in a POST body before automatic first-time upload can be enabled safely."
  return 1
}

# ══════════════════════════════════════════════════════════════════════════════
#  Deploy: Renewal — ReplaceCertificate (UpdateMode=new)
# ══════════════════════════════════════════════════════════════════════════════

_byteplus_renewal_deploy() {
  _info "Replacing old certificate '$_old_cert_id' (UpdateMode=new)..."
  _err "Refusing to replace certificate material because this hook passes PublicKey/PrivateKey as request parameters."
  _err "Uploading a private key in the request URL can leak it via logs, proxies, and process listings."
  _err "Please replace the certificate in BytePlus manually for renewal until this hook is updated to send PublicKey and PrivateKey in a POST body safely."
  return 1
}

# ══════════════════════════════════════════════════════════════════════════════
#  Delete old certificate (with retry)
# ══════════════════════════════════════════════════════════════════════════════

_byteplus_delete_old_cert() {
  _del_cert_id="$1"

  _info "Waiting 5s for cert status to settle..."
  _sleep 5

  _info "Deleting old certificate '$_del_cert_id'..."
  _del_response=$(_byteplus_alb_api "DeleteCertificate" "CertificateId=${_del_cert_id}")

  if echo "$_del_response" | grep -q '"Error"'; then
    _info "Delete failed, retrying in 10s..."
    _sleep 10
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
  _sorted_query=$(echo "$_query_params" | tr '&' '\n' | LC_ALL=C sort | tr '\n' '&' | sed 's/&$//')

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

  # Do not log _canonical_request because the query string may contain
  # URL-encoded certificate or private key material.

  # Hash of canonical request
  # _digest is provided by acme.sh and works across OpenSSL versions.
  _cr_hash=$(printf '%s' "$_canonical_request" | _digest sha256 hex)

  # Credential scope
  _credential_scope="${_date_only}/${BYTEPLUS_REGION}/${_BYTEPLUS_SERVICE}/request"

  # String to sign
  _string_to_sign="HMAC-SHA256
${_x_date}
${_credential_scope}
${_cr_hash}"

  _debug2 _string_to_sign "$_string_to_sign"

  # Signing key derivation (HMAC chain)
  # _hmac <algo> <hex-key> reads data from stdin and returns a hex digest.
  # acme.sh's _hmac abstracts away OpenSSL version differences, so this works
  # on both modern (-mac HMAC -macopt hexkey:) and older (-hmac) OpenSSL builds.
  #
  # The first step seeds the chain from the raw secret key, so we convert it
  # to hex first with _hex_dump (also an acme.sh built-in).
  _secret_hex=$(printf '%s' "$BYTEPLUS_SECRET_KEY" | _hex_dump | tr -d ' \n')
  _k_date=$(printf '%s' "$_date_only" | _hmac sha256 "$_secret_hex" hex)
  _k_region=$(printf '%s' "$BYTEPLUS_REGION" | _hmac sha256 "$_k_date" hex)
  _k_service=$(printf '%s' "$_BYTEPLUS_SERVICE" | _hmac sha256 "$_k_region" hex)
  _k_signing=$(printf '%s' "request" | _hmac sha256 "$_k_service" hex)

  # Final signature
  _signature=$(printf '%s' "$_string_to_sign" | _hmac sha256 "$_k_signing" hex)

  # Authorization header
  _auth="HMAC-SHA256 Credential=${BYTEPLUS_ACCESS_KEY}/${_credential_scope}, SignedHeaders=${_signed_headers}, Signature=${_signature}"

  _secure_debug2 _auth "$_auth"

  # Send request parameters in the POST body instead of the URL query string.
  # This avoids exposing sensitive or large values in debug-logged URLs and
  # reduces the risk of exceeding URL length limits.
  _url="https://${_BYTEPLUS_HOST}/"
  _body="$_sorted_query"

  _saved_H1="${_H1:-}"
  _saved_H2="${_H2:-}"
  _saved_H3="${_H3:-}"
  _saved_H4="${_H4:-}"
  _saved_H5="${_H5:-}"

  _H1="Authorization: ${_auth}"
  _H2="X-Date: ${_x_date}"
  _H3="Host: ${_BYTEPLUS_HOST}"
  _H4="Content-Type: application/x-www-form-urlencoded"
  _H5=""

  _response="$(_post "$_body" "$_url" "" "POST")"
  _request_ret="$?"

  _H1="$_saved_H1"
  _H2="$_saved_H2"
  _H3="$_saved_H3"
  _H4="$_saved_H4"
  _H5="$_saved_H5"

  if [ "$_request_ret" != "0" ]; then
    _err "byteplus_alb_api request failed for [$_action]"
    return 1
  fi
  _debug2 "_byteplus_alb_api response [$_action]" "$_response"
  printf '%s' "$_response"
}

# ══════════════════════════════════════════════════════════════════════════════
#  URL encode (RFC 3986)
# ══════════════════════════════════════════════════════════════════════════════

_byteplus_urlencode() {
  printf '%s' "$1" | _url_encode
}
