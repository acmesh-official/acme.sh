#!/usr/bin/env sh
# Deploy hook for UniFi OS Server (self-hosted).
#
# Supports:
#   - UniFi OS Server on macOS
#   - UniFi OS Server on Linux
#   - UniFi OS Server on Windows should also work (runs under WSL2), but
#     has not been tested.
#
#       Tested on: Ubuntu 26.04 (remote) and macOS 26.6 (local).
#
# This is a different product from the Cloud Key / UDM hardware and
# self-hosted Unifi Controller covered by the `unifi` deploy hook above
# (that hook already covers Cloud Key running UnifiOS v2.0.0+/Gen2/2+) --
# this hook targets the separately-installed, self-hosted "UniFi OS Server"
# application instead, which stores certificates in its own Postgres
# database via a local REST API rather than a Java keystore, so the `unifi`
# hook's approach does not apply here.
#
# UniFi OS Server exposes a local REST API on its management port (default
# 11443) that its own web UI uses for certificate management:
#   POST   /api/auth/login                  - session login (cookie + JWT)
#   GET    /api/userCertificates             - list uploaded certificates
#   POST   /api/userCertificates             - upload a new certificate
#   DELETE /api/userCertificates/{id}         - remove a certificate
#   PUT    /api/userCertificates/{id}/status  - activate/deactivate a certificate
#
# This was reverse-engineered from the browser's Network tab while using the
# real GUI upload/activate/delete flow -- it is undocumented but is the same
# code path the UI uses, so it's far more robust than editing settings.yaml,
# http/local-certs.conf, or the underlying Postgres user_certificates table
# directly (all of which are also touched by this API, but only as a result
# of the app's own internal logic, which handles cert parsing, active-cert
# bookkeeping, and nginx config regeneration correctly on its own).
#
# Auth: POST /api/auth/login returns a `TOKEN` cookie containing a JWT whose
# payload has a `csrfToken` claim. That value must be echoed back as the
# `x-csrf-token` header on every subsequent state-changing request (a classic
# double-submit CSRF pattern). No other cookies were found to be necessary.
#
# Uses core acme.sh helpers throughout (_post/_get, _json_encode,
# _durl_replace_base64, _dbase64, _egrep_o) rather than raw curl -k or
# python3, so HTTPS_INSECURE, the wget fallback, --debug tracing, and
# CA_BUNDLE are all honored the same as every other hook. The management
# API's cert is self-signed (it's a management-only port, not meant for
# public exposure), so HTTPS_INSECURE=1 must be set in the environment for
# this hook to connect -- see Settings below.
#
# Design: rather than persisting a certificate ID between renewals, this
# hook looks up any existing certificate row named after the domain via the
# live API on every run. It uploads and activates the new certificate
# *before* removing the old one, so a failure partway through never leaves
# the server without a valid active cert -- worst case, a stale duplicate
# entry is left behind for the next run (or a manual GUI cleanup) rather
# than the server falling back to its self-signed default.
#
# Settings:
#   DEPLOY_UNIFIOS_HOST - base URL of the management API
#     (default: "https://localhost:11443")
#   DEPLOY_UNIFIOS_USERNAME - UniFi OS Server admin username (required)
#   DEPLOY_UNIFIOS_PASSWORD - UniFi OS Server admin password (required)
#
# Example:
#   export HTTPS_INSECURE=1
#   export DEPLOY_UNIFIOS_USERNAME="acmeuser"
#   export DEPLOY_UNIFIOS_PASSWORD="xxxxx"
#   acme.sh --deploy -d example.com --deploy-hook unifios
#
# Please report bugs to https://github.com/acmesh-official/acme.sh/issues/7182

_uos_response_code() {
  _egrep_o <"$HTTP_HEADER" "^HTTP[^ ]* .*$" | cut -d " " -f 2-100 | tr -d "\f\n" | _egrep_o "^[0-9]*"
}

_uos_response_cookie() {
  # $1 = cookie name
  grep <"$HTTP_HEADER" -i "^Set-Cookie:" | grep -i "\W$1=" | _tail_n 1 | _egrep_o "$1=[^;]*" | _head_n 1
}

unifios_deploy() {
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

  _getdeployconf DEPLOY_UNIFIOS_HOST
  DEPLOY_UNIFIOS_HOST="${DEPLOY_UNIFIOS_HOST:-https://localhost:11443}"
  _savedeployconf DEPLOY_UNIFIOS_HOST "$DEPLOY_UNIFIOS_HOST"
  _debug DEPLOY_UNIFIOS_HOST "$DEPLOY_UNIFIOS_HOST"

  _getdeployconf DEPLOY_UNIFIOS_USERNAME
  _getdeployconf DEPLOY_UNIFIOS_PASSWORD

  if [ -z "$DEPLOY_UNIFIOS_USERNAME" ] || [ -z "$DEPLOY_UNIFIOS_PASSWORD" ]; then
    _err "DEPLOY_UNIFIOS_USERNAME and DEPLOY_UNIFIOS_PASSWORD must be set."
    return 1
  fi
  _debug DEPLOY_UNIFIOS_USERNAME "$DEPLOY_UNIFIOS_USERNAME"
  _secure_debug DEPLOY_UNIFIOS_PASSWORD "$DEPLOY_UNIFIOS_PASSWORD"

  _info "Logging in to UniFi OS Server API at $DEPLOY_UNIFIOS_HOST..."

  # _json_encode always appends a trailing "\n" escape, even to input with
  # no trailing newline (it normalizes via `echo`, unconditionally adding
  # one). That's harmless for the key/cert file content below, which
  # legitimately ends in a real newline anyway, but wrong for these plain
  # strings -- strip the spurious escape it leaves behind.
  _uos_user_json="$(printf '%s' "$DEPLOY_UNIFIOS_USERNAME" | _json_encode)"
  _uos_user_json="${_uos_user_json%\\n}"
  _uos_pass_json="$(printf '%s' "$DEPLOY_UNIFIOS_PASSWORD" | _json_encode)"
  _uos_pass_json="${_uos_pass_json%\\n}"
  _login_body="{\"username\":\"$_uos_user_json\",\"password\":\"$_uos_pass_json\",\"token\":\"\",\"rememberMe\":false}"

  _login_json="$(_post "$_login_body" "$DEPLOY_UNIFIOS_HOST/api/auth/login" "" "POST" "application/json")"
  _login_code="$(_uos_response_code)"

  if [ "$_login_code" != "200" ]; then
    _err "Login failed (HTTP $_login_code)."
    _err "Response: $_login_json"
    return 1
  fi

  # Credentials are proven correct now -- save them, rather than only at the
  # very end, so a later step failing doesn't discard a working login.
  _savedeployconf DEPLOY_UNIFIOS_USERNAME "$DEPLOY_UNIFIOS_USERNAME"
  _savedeployconf DEPLOY_UNIFIOS_PASSWORD "$DEPLOY_UNIFIOS_PASSWORD"

  _uos_token="$(_uos_response_cookie TOKEN)"
  if [ -z "$_uos_token" ]; then
    _err "Login succeeded but no TOKEN cookie was returned."
    return 1
  fi

  _H1="Cookie: $_uos_token"
  export _H1

  _uos_jwt_payload="$(echo "$_uos_token" | cut -d '=' -f 2- | cut -d '.' -f 2)"
  _uos_csrf="$(_durl_replace_base64 "$_uos_jwt_payload" | _dbase64 | _egrep_o '"csrfToken":"[^"]*"' | cut -d '"' -f 4)"
  if [ -z "$_uos_csrf" ]; then
    _err "Could not extract csrfToken from session token."
    return 1
  fi

  _H2="x-csrf-token: $_uos_csrf"
  export _H2

  _info "Checking for an existing '$_cdomain' certificate entry..."
  _list_json="$(_get "$DEPLOY_UNIFIOS_HOST/api/userCertificates")"
  _old_ids="$(echo "$_list_json" | sed 's/},{/}\n{/g' | grep "\"name\":\"$_cdomain\"" | _egrep_o '"id":"[^"]*"' | cut -d '"' -f 4)"
  _debug _old_ids "$_old_ids"

  _info "Uploading new certificate..."
  _uos_key_json="$(_json_encode <"$_ckey")"
  _uos_cert_json="$(_json_encode <"$_cfullchain")"
  _create_body="{\"name\":\"$_cdomain\",\"key\":\"$_uos_key_json\",\"cert\":\"$_uos_cert_json\"}"

  _create_json="$(_post "$_create_body" "$DEPLOY_UNIFIOS_HOST/api/userCertificates" "" "POST" "application/json")"
  _create_code="$(_uos_response_code)"

  if [ "$_create_code" = "201" ]; then
    _new_id="$(echo "$_create_json" | _egrep_o '"id":"[^"]*"' | _head_n 1 | cut -d '"' -f 4)"
    if [ -z "$_new_id" ]; then
      _err "Could not determine new certificate ID from upload response."
      return 1
    fi
  elif [ "$_create_code" = "400" ] && echo "$_create_json" | grep -q "USER_CERTIFICATE_DUPLICATE" && [ -n "$_old_ids" ]; then
    # The server already has an entry matching this exact name+fingerprint --
    # most likely a retry after a prior run already uploaded it (a real
    # renewal always produces a new fingerprint, so this shouldn't happen in
    # normal cron use). Reuse the existing entry instead of failing, and
    # don't delete it below.
    _new_id="$(printf '%s\n' "$_old_ids" | _head_n 1)"
    _info "Certificate already present as entry $_new_id; reusing it."
    _old_ids="$(printf '%s\n' "$_old_ids" | grep -v "^$_new_id$")"
  else
    _err "Certificate upload failed (HTTP $_create_code)."
    _err "Response: $_create_json"
    return 1
  fi

  _info "Activating certificate $_new_id..."
  _activate_json="$(_post '{"active":true}' "$DEPLOY_UNIFIOS_HOST/api/userCertificates/$_new_id/status" "" "PUT" "application/json")"
  _activate_code="$(_uos_response_code)"

  if [ "$_activate_code" != "200" ]; then
    _err "Failed to activate new certificate (HTTP $_activate_code)."
    _err "Response: $_activate_json"
    return 1
  fi

  # The new cert is live at this point, so a failure to clean up the old
  # entry is logged but does not fail the deploy -- the server is already
  # serving a valid certificate.
  for _old_id in $_old_ids; do
    _info "Removing superseded certificate entry $_old_id..."
    _del_json="$(_post "" "$DEPLOY_UNIFIOS_HOST/api/userCertificates/$_old_id" "" "DELETE")"
    _del_code="$(_uos_response_code)"
    if [ "$_del_code" != "204" ] && [ "$_del_code" != "200" ]; then
      _err "Failed to delete superseded certificate $_old_id (HTTP $_del_code) -- leaving it in place."
      _err "Response: $_del_json"
    fi
  done

  _info "UniFi OS Server certificate deployed and activated successfully."
  return 0
}
