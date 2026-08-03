#!/usr/bin/env sh
# Deploy hook for UniFi OS Server for Mac.
#
# UniFi OS Server for Mac exposes a local REST API on its management port
# (default 11443) that the web UI itself uses for certificate management:
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
# This hook is macOS-only (the app itself only exists on macOS), so it uses
# python3 (bundled with macOS) for JSON handling rather than sed/grep, which
# is far more robust against arbitrary JSON structure than hand-rolled
# parsing would be.
#
# Design: rather than persisting a certificate ID between renewals, this
# hook looks up any existing certificate row named after the domain via the
# live API on every run, deletes it, uploads the new one, and activates it.
# This avoids any local state that could go stale (this is exactly the kind
# of drift that caused problems with an earlier settings.yaml-editing
# version of this hook).
#
# Settings:
#   DEPLOY_UNIFIOS_MAC_HOST - base URL of the management API
#     (default: "https://localhost:11443")
#   DEPLOY_UNIFIOS_MAC_USERNAME - local UniFi OS Server admin username (required)
#   DEPLOY_UNIFIOS_MAC_PASSWORD - local UniFi OS Server admin password (required)
#
# Example:
#   export DEPLOY_UNIFIOS_MAC_USERNAME="acmeuser"
#   export DEPLOY_UNIFIOS_MAC_PASSWORD="xxxxx"
#   acme.sh --deploy -d example.com --deploy-hook unifios_mac

unifios_mac_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  if ! _exists python3; then
    _err "python3 is required for the unifios_mac deploy hook but was not found."
    return 1
  fi

  _getdeployconf DEPLOY_UNIFIOS_MAC_HOST
  _getdeployconf DEPLOY_UNIFIOS_MAC_USERNAME
  _getdeployconf DEPLOY_UNIFIOS_MAC_PASSWORD

  DEPLOY_UNIFIOS_MAC_HOST="${DEPLOY_UNIFIOS_MAC_HOST:-https://localhost:11443}"

  if [ -z "$DEPLOY_UNIFIOS_MAC_USERNAME" ] || [ -z "$DEPLOY_UNIFIOS_MAC_PASSWORD" ]; then
    _err "DEPLOY_UNIFIOS_MAC_USERNAME and DEPLOY_UNIFIOS_MAC_PASSWORD must be set."
    return 1
  fi

  _uos_cookiejar="$(_mktemp)"

  _uos_cleanup() {
    [ -f "$_uos_cookiejar" ] && rm -f "$_uos_cookiejar"
  }

  _info "Logging in to UniFi OS Server API at $DEPLOY_UNIFIOS_MAC_HOST..."
  _login_body=$(python3 -c '
import json, sys
print(json.dumps({"username": sys.argv[1], "password": sys.argv[2], "token": "", "rememberMe": False}))
' "$DEPLOY_UNIFIOS_MAC_USERNAME" "$DEPLOY_UNIFIOS_MAC_PASSWORD")

  _login_out=$(curl -sk -c "$_uos_cookiejar" -H "Content-Type: application/json" \
    -d "$_login_body" -w '\n%{http_code}' "$DEPLOY_UNIFIOS_MAC_HOST/api/auth/login")
  _login_code=$(echo "$_login_out" | tail -n1)

  if [ "$_login_code" != "200" ]; then
    _err "Login failed (HTTP $_login_code)."
    _uos_cleanup
    return 1
  fi

  _uos_token=$(awk -F'\t' '$6=="TOKEN"{print $7}' "$_uos_cookiejar")
  if [ -z "$_uos_token" ]; then
    _err "Login succeeded but no TOKEN cookie was returned."
    _uos_cleanup
    return 1
  fi

  _uos_csrf=$(python3 -c '
import base64, json, sys
tok = sys.argv[1]
payload = tok.split(".")[1]
payload += "=" * (-len(payload) % 4)
data = json.loads(base64.urlsafe_b64decode(payload))
print(data["csrfToken"])
' "$_uos_token" 2>/dev/null)

  if [ -z "$_uos_csrf" ]; then
    _err "Could not extract csrfToken from session token."
    _uos_cleanup
    return 1
  fi

  _info "Checking for an existing '$_cdomain' certificate entry..."
  _list_json=$(curl -sk -b "$_uos_cookiejar" -H "x-csrf-token: $_uos_csrf" \
    "$DEPLOY_UNIFIOS_MAC_HOST/api/userCertificates")

  _old_ids=$(echo "$_list_json" | python3 -c '
import json, sys
domain = sys.argv[1]
try:
    certs = json.loads(sys.stdin.read())
except Exception:
    certs = []
for c in certs:
    if c.get("name") == domain:
        print(c["id"])
' "$_cdomain")

  for _old_id in $_old_ids; do
    _info "Deleting existing certificate entry $_old_id..."
    _del_code=$(curl -sk -b "$_uos_cookiejar" -H "x-csrf-token: $_uos_csrf" \
      -X DELETE -o /dev/null -w '%{http_code}' \
      "$DEPLOY_UNIFIOS_MAC_HOST/api/userCertificates/$_old_id")
    if [ "$_del_code" != "204" ] && [ "$_del_code" != "200" ]; then
      _err "Failed to delete old certificate $_old_id (HTTP $_del_code)."
      _uos_cleanup
      return 1
    fi
  done

  _info "Uploading new certificate..."
  _create_body=$(python3 -c '
import json, sys
name = sys.argv[1]
with open(sys.argv[2]) as f:
    key = f.read()
with open(sys.argv[3]) as f:
    cert = f.read()
print(json.dumps({"name": name, "key": key, "cert": cert}))
' "$_cdomain" "$_ckey" "$_ccert")

  _create_out=$(curl -sk -b "$_uos_cookiejar" -H "Content-Type: application/json" \
    -H "x-csrf-token: $_uos_csrf" -d "$_create_body" -w '\n%{http_code}' \
    "$DEPLOY_UNIFIOS_MAC_HOST/api/userCertificates")
  _create_code=$(echo "$_create_out" | tail -n1)
  _create_json=$(echo "$_create_out" | sed '$d')

  if [ "$_create_code" != "201" ]; then
    _err "Certificate upload failed (HTTP $_create_code)."
    _uos_cleanup
    return 1
  fi

  _new_id=$(echo "$_create_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null)
  if [ -z "$_new_id" ]; then
    _err "Could not determine new certificate ID from upload response."
    _uos_cleanup
    return 1
  fi

  _info "Activating certificate $_new_id..."
  _activate_code=$(curl -sk -b "$_uos_cookiejar" -H "Content-Type: application/json" \
    -H "x-csrf-token: $_uos_csrf" -X PUT -d '{"active":true}' \
    -o /dev/null -w '%{http_code}' \
    "$DEPLOY_UNIFIOS_MAC_HOST/api/userCertificates/$_new_id/status")

  if [ "$_activate_code" != "200" ]; then
    _err "Failed to activate new certificate (HTTP $_activate_code)."
    _uos_cleanup
    return 1
  fi

  _uos_cleanup

  _savedeployconf DEPLOY_UNIFIOS_MAC_HOST "$DEPLOY_UNIFIOS_MAC_HOST"
  _savedeployconf DEPLOY_UNIFIOS_MAC_USERNAME "$DEPLOY_UNIFIOS_MAC_USERNAME"
  _savedeployconf DEPLOY_UNIFIOS_MAC_PASSWORD "$DEPLOY_UNIFIOS_MAC_PASSWORD"

  _info "UniFi OS Server certificate deployed and activated successfully."
  return 0
}
