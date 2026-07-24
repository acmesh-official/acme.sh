#!/usr/bin/env sh

# Here is a script to deploy cert to a Shelly Gen3+ device.
# Deploy the HTTPS server certificate to a Shelly device on the local network.
#
# ```sh
# export SHELLY_HOST=192.168.1.100
# export SHELLY_PASSWORD=mysecret    # only if auth is enabled on the device
# acme.sh --deploy -d shelly.example.com --deploy-hook shelly
# ```
#
# Environment variables:
#   SHELLY_HOST      (required)  IP or hostname of the Shelly device
#   SHELLY_PASSWORD  (optional)  Admin password for digest authentication.
#                                Omit if auth is disabled on the device.
#   SHELLY_USER      (optional)  Username for auth. Default: admin
#   SHELLY_REBOOT     (optional)  Set to "0" to skip auto-reboot.
#                                Default: 1 (reboot after upload)
#
# Requirements:
#   - Shelly Gen3+ device (Gen4 recommended)
#   - Firmware 2.0.0+ for HTTPS server certificate support
#   - curl or wget
#   - openssl (for SHA-256 digest and random cnonce)
#
# The device must be reachable via HTTP on the local network.
# The hook uploads the fullchain.pem and private key,
# then reboots the device to apply the new certificate.
#
# Authentication uses standard RFC 7616 HTTP Digest (SHA-256) since
# firmware 2.0.0. The JSON-RPC auth object is not used for HTTP transport.
#
# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
shelly_deploy() {
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

  _getdeployconf SHELLY_HOST
  _getdeployconf SHELLY_PASSWORD
  _getdeployconf SHELLY_USER
  _getdeployconf SHELLY_REBOOT

  _debug SHELLY_HOST "$SHELLY_HOST"
  _debug SHELLY_USER "$SHELLY_USER"
  _secure_debug SHELLY_PASSWORD "$SHELLY_PASSWORD"
  _debug SHELLY_REBOOT "$SHELLY_REBOOT"

  if [ -z "$SHELLY_HOST" ]; then
    _err "SHELLY_HOST is required. Please set the IP or hostname of your Shelly device."
    return 1
  fi

  SHELLY_USER="${SHELLY_USER:-admin}"
  SHELLY_REBOOT="${SHELLY_REBOOT:-1}"

  _savedeployconf SHELLY_HOST "$SHELLY_HOST"
  _savedeployconf SHELLY_PASSWORD "$SHELLY_PASSWORD"
  _savedeployconf SHELLY_USER "$SHELLY_USER"
  _savedeployconf SHELLY_REBOOT "$SHELLY_REBOOT"

  # --- Auth handshake (only if password is set) ---
  _shelly_auth_header=""
  if [ -n "$SHELLY_PASSWORD" ]; then
    _info "Authenticating to Shelly device at $SHELLY_HOST"
    if ! _shelly_handshake; then
      _err "Authentication handshake failed. Check SHELLY_PASSWORD and device accessibility."
      return 1
    fi
    _info "Authentication successful"
  fi

  # --- Upload certificate ---
  _info "Uploading certificate to Shelly device at $SHELLY_HOST"
  if ! _shelly_upload_cert; then
    _err "Certificate upload failed"
    return 1
  fi

  # --- Upload key ---
  _info "Uploading private key to Shelly device"
  if ! _shelly_upload_key; then
    _err "Private key upload failed"
    return 1
  fi

  _info "Certificate and key uploaded successfully"

  # --- Reboot ---
  if [ "$SHELLY_REBOOT" != "0" ]; then
    _info "Rebooting Shelly device to apply certificate"
    # Reboot may close the connection before sending a response
    _shelly_rpc "Shelly.Reboot" '{}' || _debug "Reboot may have closed connection (expected)"
    _info "Reboot command sent. Device will restart shortly."
  else
    _info "Skipping reboot (SHELLY_REBOOT=0). Certificate will apply on next restart."
  fi

  # Clear auth header so it does not leak to other hooks
  export _H1=""

  return 0
}

# --- Helper functions ---

# Perform RFC 7616 HTTP Digest auth handshake.
# Sets _shelly_auth_header on success (the Authorization header value).
_shelly_handshake() {
  _inithttp

  _debug "Probing device for auth challenge"

  # Use a protected method (Shelly.GetStatus) to trigger 401.
  # Shelly.GetDeviceInfo is excluded from auth and would miss the challenge.
  _post '{"id":1,"method":"Shelly.GetStatus"}' \
    "http://${SHELLY_HOST}/rpc" "" "" "application/json"

  # Detect auth from HTTP status line rather than response body
  if ! _shelly_has_auth_challenge "$HTTP_HEADER"; then
    # No auth challenge — device accepted the request without credentials
    _debug "Device responded without auth challenge. Proceeding without auth."
    return 0
  fi

  _shelly_realm="$(grep -i '^WWW-Authenticate:' "$HTTP_HEADER" | sed 's/.*realm="//;s/".*//')"
  _shelly_nonce="$(grep -i '^WWW-Authenticate:' "$HTTP_HEADER" | sed 's/.*nonce="//;s/".*//')"
  _shelly_qop="$(grep -i '^WWW-Authenticate:' "$HTTP_HEADER" | sed 's/.*qop="//;s/".*//')"

  if [ -z "$_shelly_nonce" ]; then
    _err "Failed to extract nonce from WWW-Authenticate header. Is SHELLY_PASSWORD correct?"
    return 1
  fi

  _shelly_qop="${_shelly_qop:-auth}"

  _debug "Shelly realm: $_shelly_realm"
  _debug "Shelly qop: $_shelly_qop"
  _secure_debug "Shelly nonce" "$_shelly_nonce"

  # ha1 = SHA256(username:realm:password)
  _shelly_ha1="$(printf '%s' "${SHELLY_USER}:${_shelly_realm}:${SHELLY_PASSWORD}" | _digest sha256 hex)"
  _secure_debug "Shelly ha1" "$_shelly_ha1"

  # Generate client nonce (openssl is required for _digest, so always available)
  _shelly_cnonce="$(${ACME_OPENSSL_BIN:-openssl} rand -hex 8 2>/dev/null)"
  _debug "Shelly cnonce: $_shelly_cnonce"

  # Build the digest Authorization header value (stored for reuse)
  _shelly_nc=1
  _shelly_build_auth_header

  return 0
}

# Check whether the HTTP response headers contain a digest auth challenge.
# Returns 0 (true) if a 401 with WWW-Authenticate is present.
_shelly_has_auth_challenge() {
  _shelly_headers_file="$1"
  _shelly_status="$(grep -i '^HTTP/' "$_shelly_headers_file" | _tail_n 1 | awk '{print $2}')"
  [ "$_shelly_status" = "401" ] && grep -qi '^WWW-Authenticate:' "$_shelly_headers_file"
}

# Build or rebuild the RFC 7616 Authorization header.
# Uses: _shelly_ha1, _shelly_nonce, _shelly_cnonce, _shelly_qop, _shelly_realm, _shelly_nc
# Sets: _shelly_auth_header
_shelly_build_auth_header() {
  _shelly_nc_hex="$(printf '%08x' "$_shelly_nc")"

  # ha2 = SHA256(POST:/rpc)
  _shelly_ha2="$(printf '%s' "POST:/rpc" | _digest sha256 hex)"

  # response = SHA256(ha1:nonce:nc:cnonce:qop:ha2)
  _shelly_digest_response="$(printf '%s' "${_shelly_ha1}:${_shelly_nonce}:${_shelly_nc_hex}:${_shelly_cnonce}:${_shelly_qop}:${_shelly_ha2}" | _digest sha256 hex)"

  # Build the Authorization header value (without the "Authorization: " prefix)
  _shelly_auth_header="Digest username=\"${SHELLY_USER}\", realm=\"${_shelly_realm}\", nonce=\"${_shelly_nonce}\", uri=\"/rpc\", qop=${_shelly_qop}, nc=${_shelly_nc_hex}, cnonce=\"${_shelly_cnonce}\", response=\"${_shelly_digest_response}\", algorithm=SHA-256"

  _secure_debug "Authorization header" "$_shelly_auth_header"
}

# Make a Shelly JSON-RPC call.
# Usage: _shelly_rpc <method> <params_json>
# Returns 0 on success, 1 on error.
_shelly_rpc() {
  _shelly_method="$1"
  _shelly_params="$2"

  _shelly_body='{"id":1,"method":"'"$_shelly_method"'","params":'"$_shelly_params"'}'

  _debug "RPC method: $_shelly_method"
  _debug2 "RPC body: $_shelly_body"

  # shellcheck disable=SC2090
  if [ -n "$_shelly_auth_header" ]; then
    export _H1="Authorization: $_shelly_auth_header"
  else
    export _H1=""
  fi

  _post "$_shelly_body" "http://${SHELLY_HOST}/rpc" "" "" "application/json"
  _shelly_ret=$?

  if [ "$_shelly_ret" != "0" ]; then
    _err "HTTP request failed for $_shelly_method (curl/wget error $_shelly_ret)"
    return 1
  fi

  # Empty response means something went wrong (auth required but not provided, etc.)
  if [ -z "$response" ]; then
    _err "Empty response from Shelly device. If authentication is enabled on the device, set SHELLY_PASSWORD."
    return 1
  fi

  # Validate response looks like a Shelly JSON-RPC response.
  # Catches non-JSON responses such as HTTP 429 "Too Many Requests" which
  # would otherwise pass the empty and "error" checks below.
  if ! _startswith "$response" '{' || ! _contains "$response" '"id"'; then
    _err "Invalid response from Shelly device: $response"
    return 1
  fi

  # Check for JSON-RPC error in response
  if _contains "$response" '"error"'; then
    _err "RPC error from Shelly: $response"
    return 1
  fi

  _debug "RPC response: $response"

  # Increment nonce counter and rebuild auth header for next request
  if [ -n "$_shelly_auth_header" ]; then
    _shelly_nc=$((_shelly_nc + 1))
    _shelly_build_auth_header
  fi

  return 0
}

# Upload the certificate to the device.
# Note: We do NOT clear the existing certificate first, because the Shelly
# auto-removes all three files (cert, key, CA) when any one is cleared.
# Uploading overwrites in place — no clearing needed.
_shelly_upload_cert() {
  _shelly_cert_data="$(_json_encode <"$_cfullchain")"

  _debug "Uploading certificate"
  if ! _shelly_rpc "Shelly.PutHTTPServerCert" '{"data":"'"$_shelly_cert_data"'"}'; then
    _err "Failed to upload certificate to device"
    return 1
  fi

  return 0
}

# Upload the private key to the device.
# Note: Do not clear first — see _shelly_upload_cert for rationale.
_shelly_upload_key() {
  _shelly_key_data="$(_json_encode <"$_ckey")"

  _debug "Uploading key"
  if ! _shelly_rpc "Shelly.PutHTTPServerKey" '{"data":"'"$_shelly_key_data"'"}'; then
    _err "Failed to upload key to device"
    return 1
  fi

  return 0
}
