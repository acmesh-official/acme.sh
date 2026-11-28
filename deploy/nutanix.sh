#!/usr/bin/env sh

# Script to deploy a certificate to a Nutanix Prism Central or Prism Element.
#
# The API user needs permission to replace the SSL certificate.
#
# Returns 0 when successful, otherwise an error.
#
# The following environment variables must be set on the first run and are
# then saved (base64 encoded) to the deploy configuration:
#
#   export NUTANIX_USER="admin"           # required
#   export NUTANIX_PASS="password"        # required
#   export NUTANIX_HOST="prism.example.com" # required, hostname or IP
#
# Optional:
#
#   export NUTANIX_INSECURE="1"           # skip TLS verification of Prism
#
# The Prism REST API listens on port 9440.

#domain keyfile certfile cafile fullchain
nutanix_deploy() {
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

  # Load config: env vars take precedence over previously saved values.
  _getdeployconf NUTANIX_USER
  _getdeployconf NUTANIX_PASS
  _getdeployconf NUTANIX_HOST
  _getdeployconf NUTANIX_INSECURE

  _secure_debug NUTANIX_USER "$NUTANIX_USER"
  _secure_debug NUTANIX_PASS "$NUTANIX_PASS"
  _debug NUTANIX_HOST "$NUTANIX_HOST"
  _debug NUTANIX_INSECURE "$NUTANIX_INSECURE"

  if [ -z "$NUTANIX_HOST" ]; then
    _err "NUTANIX_HOST is not set. Please export NUTANIX_HOST before deploying."
    return 1
  fi
  if [ -z "$NUTANIX_USER" ]; then
    _err "NUTANIX_USER is not set. Please export NUTANIX_USER before deploying."
    return 1
  fi
  if [ -z "$NUTANIX_PASS" ]; then
    _err "NUTANIX_PASS is not set. Please export NUTANIX_PASS before deploying."
    return 1
  fi

  # Prism supports RSA_2048, ECDSA_256 and ECDSA_384 keys. Derive the type
  # from the private key instead of hardcoding it so ECC certs also work.
  _key_type=$(_nutanix_key_type "$_ckey")
  if [ -z "$_key_type" ]; then
    _err "Unable to determine a Prism keyType from $_ckey."
    _err "Nutanix Prism only supports RSA 2048-bit, ECDSA P-256 and ECDSA P-384 keys."
    return 1
  fi
  _info "Using Prism keyType $_key_type"

  # Opt-in TLS verification skip. Prism ships with a self-signed cert until
  # the first custom certificate is installed, so this is often needed once.
  if [ "$NUTANIX_INSECURE" = "1" ]; then
    _info "NUTANIX_INSECURE=1, skipping TLS verification of $NUTANIX_HOST"
    export HTTPS_INSECURE=1
  fi

  # Basic auth header. Passing credentials this way keeps the password out
  # of the process list (unlike curl --user).
  _H1="Authorization: Basic $(printf "%s" "$NUTANIX_USER:$NUTANIX_PASS" | _base64)"
  export _H1

  _info "Building multipart upload request"
  nl="\0015\0012"
  delim="--------------------------$(_utc_date | tr -d -- '-: ')"
  content="--$delim${nl}Content-Disposition: form-data; name=\"keyType\"${nl}${nl}$_key_type"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"key\"; filename=\"$(basename "$_ckey")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ckey")"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"cert\"; filename=\"$(basename "$_ccert")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ccert")"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"caChain\"; filename=\"$(basename "$_cca")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_cca")"
  content="$content${nl}--$delim--${nl}"
  content="$(printf "%b_" "$content")"
  content="${content%_}" # protect the trailing newline

  _nutanix_url="https://$NUTANIX_HOST:9440/PrismGateway/services/rest/v1/keys/pem/import"
  _info "Uploading certificate to $NUTANIX_HOST"
  _response=$(_post "$content" "$_nutanix_url" "" "POST" "multipart/form-data; boundary=${delim}")
  _ret="$?"
  _debug3 _response "$_response"

  if [ "$_ret" != "0" ]; then
    _err "Certificate upload to $NUTANIX_HOST failed (transport error $_ret)."
    return 1
  fi
  # A successful import returns the certificate details; failures return a
  # JSON error object. Treat any error/fault indication as a failure.
  if echo "$_response" | _egrep_o '"(error|message_list|reason)"' >/dev/null 2>&1; then
    _err "Certificate upload to $NUTANIX_HOST failed: $_response"
    return 1
  fi

  _info "Certificate successfully deployed to $NUTANIX_HOST"

  # Only persist config once the deploy has actually succeeded.
  _savedeployconf NUTANIX_USER "$NUTANIX_USER" 1
  _savedeployconf NUTANIX_PASS "$NUTANIX_PASS" 1
  _savedeployconf NUTANIX_HOST "$NUTANIX_HOST"
  _savedeployconf NUTANIX_INSECURE "$NUTANIX_INSECURE"

  return 0
}

# Map a private key to the keyType string expected by the Prism API.
# keyfile
_nutanix_key_type() {
  _ntx_key="$1"
  if _isRSA "$_ntx_key" >/dev/null 2>&1; then
    _ntx_bits=$(${ACME_OPENSSL_BIN:-openssl} rsa -in "$_ntx_key" -noout -text 2>/dev/null | grep -i "Private-Key" | _egrep_o "[0-9]+" | head -n 1)
    _debug2 _ntx_bits "$_ntx_bits"
    echo "RSA_${_ntx_bits}"
  elif _isEcc "$_ntx_key" >/dev/null 2>&1; then
    _ntx_curve=$(${ACME_OPENSSL_BIN:-openssl} ec -in "$_ntx_key" -noout -text 2>/dev/null | grep -i "NIST CURVE" | cut -d ':' -f 2 | tr -d ' \r\n')
    _debug2 _ntx_curve "$_ntx_curve"
    case "$_ntx_curve" in
    P-256) echo "ECDSA_256" ;;
    P-384) echo "ECDSA_384" ;;
    *) return 1 ;;
    esac
  else
    return 1
  fi
}
