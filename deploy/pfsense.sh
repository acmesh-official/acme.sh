#!/usr/bin/env sh

# Deploy hook to deploy a certificate to pfSense using the pfREST API
# (https://pfrest.org). Tested with pfSense 2.9.0 and pfREST 2.10.2.
#
# The certificate is created under DEPLOY_PFSENSE_CERT_NAME, or key and
# certificate are replaced in place if it already exists. Then it is
# optionally assigned to the Unbound DNS-over-TLS listener and finally to the
# web UI, which gets restarted (the API is briefly unreachable afterwards).
#
# Preparation on the pfSense:
#
# - Install pfREST and enable key authentication:
#   https://pfrest.org/INSTALL_AND_CONFIG/
#   https://pfrest.org/AUTHENTICATION_AND_AUTHORIZATION/
# - Create the API key (System > REST API > Keys) with a user that has
#   "WebCfg - All pages". Afterwards use a dedicated user with only these
#   privileges, the key is bound to the user that creates it:
#     REST API - /api/v2/system/certificate PATCH
#     REST API - /api/v2/system/certificate POST
#     REST API - /api/v2/system/certificates GET
#     REST API - /api/v2/system/webgui/settings PATCH
#     REST API - /api/v2/services/dns_resolver/apply POST
#     REST API - /api/v2/services/dns_resolver/settings GET
#     REST API - /api/v2/services/dns_resolver/settings PATCH
# - DNS-over-TLS only: "Enable SSL/TLS Service" must already be enabled in
#   Services > DNS Resolver, otherwise Unbound is skipped.
#
# Environment variables:
#
# DEPLOY_PFSENSE_APIKEY         - (REQUIRED)
#                                 pfREST API key.
# DEPLOY_PFSENSE_HOST           - pfsense.example.com, 192.168.1.1, etc. (OPTIONAL)
#                                 Host/IP of the pfSense. Defaults to the
#                                 certificate domain, required for wildcard
#                                 certificates.
# DEPLOY_PFSENSE_PORT           - 443, 8443, etc. (OPTIONAL)
#                                 Web UI/API port. Defaults to 443.
# DEPLOY_PFSENSE_CERT_NAME      - My Certificate, etc. (OPTIONAL)
#                                 Certificate name shown in pfSense. Defaults to
#                                 the certificate domain.
# DEPLOY_PFSENSE_WEBUI          - yes/no (OPTIONAL)
#                                 Assign to the web UI and restart it. Defaults
#                                 to "yes".
# DEPLOY_PFSENSE_UNBOUND_DOT    - yes/no (OPTIONAL)
#                                 Also assign to Unbound DNS-over-TLS. Defaults
#                                 to "no".
# DEPLOY_PFSENSE_INSECURE       - yes/no (OPTIONAL)
#                                 Do not verify the pfSense TLS certificate,
#                                 needed on the first run with the self-signed
#                                 default certificate. Defaults to "no".
#
# Example:
#
# export DEPLOY_PFSENSE_APIKEY="<api key>"
# acme.sh --deploy -d pfsense.example.com --deploy-hook pfsense
#
# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
pfsense_deploy() {
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

  if [ ! -f "$_ckey" ] || [ ! -f "$_cfullchain" ]; then
    _err "Key or fullchain file not found."
    return 1
  fi

  _getdeployconf DEPLOY_PFSENSE_APIKEY
  if [ -z "$DEPLOY_PFSENSE_APIKEY" ]; then
    _err "DEPLOY_PFSENSE_APIKEY is not set."
    return 1
  fi
  _secure_debug2 DEPLOY_PFSENSE_APIKEY "$DEPLOY_PFSENSE_APIKEY"

  for _pf_var in HOST PORT CERT_NAME WEBUI UNBOUND_DOT INSECURE; do
    _getdeployconf "DEPLOY_PFSENSE_$_pf_var"
  done

  if [ -z "$DEPLOY_PFSENSE_HOST" ]; then
    if _startswith "$_cdomain" "*"; then
      _err "DEPLOY_PFSENSE_HOST must be set for wildcard certificates."
      return 1
    fi
    DEPLOY_PFSENSE_HOST="$_cdomain"
  fi
  [ -n "$DEPLOY_PFSENSE_PORT" ] || DEPLOY_PFSENSE_PORT="443"
  [ -n "$DEPLOY_PFSENSE_CERT_NAME" ] || DEPLOY_PFSENSE_CERT_NAME="$_cdomain"
  [ -n "$DEPLOY_PFSENSE_WEBUI" ] || DEPLOY_PFSENSE_WEBUI="yes"
  [ -n "$DEPLOY_PFSENSE_UNBOUND_DOT" ] || DEPLOY_PFSENSE_UNBOUND_DOT="no"
  [ -n "$DEPLOY_PFSENSE_INSECURE" ] || DEPLOY_PFSENSE_INSECURE="no"

  # pfREST rejects these characters in a certificate description
  case "$DEPLOY_PFSENSE_CERT_NAME" in
  *[\?\>\<\&/\\\"\']*)
    _err "DEPLOY_PFSENSE_CERT_NAME must not contain any of: ? > < & / \\ \" '"
    return 1
    ;;
  esac

  _debug2 DEPLOY_PFSENSE_HOST "$DEPLOY_PFSENSE_HOST"
  _debug2 DEPLOY_PFSENSE_PORT "$DEPLOY_PFSENSE_PORT"
  _debug2 DEPLOY_PFSENSE_CERT_NAME "$DEPLOY_PFSENSE_CERT_NAME"
  _debug2 DEPLOY_PFSENSE_WEBUI "$DEPLOY_PFSENSE_WEBUI"
  _debug2 DEPLOY_PFSENSE_UNBOUND_DOT "$DEPLOY_PFSENSE_UNBOUND_DOT"
  _debug2 DEPLOY_PFSENSE_INSECURE "$DEPLOY_PFSENSE_INSECURE"

  _pfsense_api_url="https://${DEPLOY_PFSENSE_HOST}:${DEPLOY_PFSENSE_PORT}/api/v2"
  if [ "$DEPLOY_PFSENSE_INSECURE" = "yes" ]; then
    export HTTPS_INSECURE=1
  fi

  _info "Looking up certificate '$DEPLOY_PFSENSE_CERT_NAME' on pfSense"
  _pfsense_call GET "/system/certificates?descr=$(printf '%s' "$DEPLOY_PFSENSE_CERT_NAME" | _url_encode)" || return 1
  _pf_id="$(printf '%s' "$_pfsense_response" | _egrep_o '"id":[0-9]+' | head -n 1 | cut -d : -f 2)"
  _pf_refid="$(printf '%s' "$_pfsense_response" | _egrep_o '"refid":"[^"]*"' | head -n 1 | cut -d '"' -f 4)"
  _debug2 "existing id/refid" "$_pf_id/$_pf_refid"

  _pf_crt="$(_json_encode <"$_cfullchain")"
  _pf_prv="$(_json_encode <"$_ckey")"

  if [ -n "$_pf_id" ] && [ -n "$_pf_refid" ]; then
    _info "Updating existing certificate (refid $_pf_refid)"
    _pfsense_call PATCH "/system/certificate" \
      "{\"id\": $_pf_id, \"crt\": \"$_pf_crt\", \"prv\": \"$_pf_prv\"}" || return 1
  else
    _info "Creating new certificate"
    _pfsense_call POST "/system/certificate" \
      "{\"descr\": \"$DEPLOY_PFSENSE_CERT_NAME\", \"type\": \"server\", \"crt\": \"$_pf_crt\", \"prv\": \"$_pf_prv\"}" || return 1
    _pf_refid="$(printf '%s' "$_pfsense_response" | _egrep_o '"refid":"[^"]*"' | head -n 1 | cut -d '"' -f 4)"
    if [ -z "$_pf_refid" ]; then
      _err "Certificate was created but no refid was returned."
      return 1
    fi
  fi

  _savedeployconf DEPLOY_PFSENSE_APIKEY "$DEPLOY_PFSENSE_APIKEY"
  for _pf_var in HOST PORT CERT_NAME WEBUI UNBOUND_DOT INSECURE; do
    _savedeployconf "DEPLOY_PFSENSE_$_pf_var" "$(eval echo "\$DEPLOY_PFSENSE_$_pf_var")"
  done

  if [ "$DEPLOY_PFSENSE_UNBOUND_DOT" = "yes" ]; then
    _pfsense_unbound_dot "$_pf_refid" || return 1
  fi

  if [ "$DEPLOY_PFSENSE_WEBUI" != "no" ]; then
    _info "Assigning certificate to the web UI and restarting it"
    _pfsense_call PATCH "/system/webgui/settings" "{\"sslcertref\": \"$_pf_refid\"}" || return 1
  fi

  _info "Certificate successfully deployed to pfSense"
  return 0
}

####################  Private functions below ##################################

# method path [body] -> sets _pfsense_response, returns 1 on non-2xx
_pfsense_call() {
  _pf_method="$1"
  _pf_path="$2"
  _pf_body="$3"

  _H1="x-api-key: $DEPLOY_PFSENSE_APIKEY"
  export _H1
  _debug "$_pf_method" "$_pfsense_api_url$_pf_path"

  if [ "$_pf_method" = "GET" ]; then
    _pfsense_response="$(_get "$_pfsense_api_url$_pf_path")"
  else
    _pfsense_response="$(_post "$_pf_body" "$_pfsense_api_url$_pf_path" "" "$_pf_method" "application/json")"
  fi
  _pf_ret=$?

  _pf_status="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
  _pfsense_response="$(printf '%s' "$_pfsense_response" | tr -d '\r\n' | sed 's/" *: */":/g')"
  _debug2 "HTTP status" "$_pf_status"
  _secure_debug3 response "$_pfsense_response"

  case "$_pf_status" in
  2[0-9][0-9])
    [ "$_pf_ret" = "0" ] && return 0
    ;;
  esac

  _pf_msg="$(printf '%s' "$_pfsense_response" | _egrep_o '"message":"[^"]*"' | head -n 1 | cut -d '"' -f 4)"
  _err "pfSense API call failed: $_pf_method $_pf_path (HTTP ${_pf_status:-none}). $_pf_msg"
  if [ "$_pf_status" = "401" ] || [ "$_pf_status" = "403" ] || [ -z "$_pf_status" ]; then
    _err "Check DEPLOY_PFSENSE_APIKEY, the user privileges and DEPLOY_PFSENSE_HOST/PORT. Use DEPLOY_PFSENSE_INSECURE=yes for an untrusted web UI certificate."
  fi
  return 1
}

# refid
_pfsense_unbound_dot() {
  _pf_dot_refid="$1"

  _info "Checking Unbound DNS-over-TLS"
  _pfsense_call GET "/services/dns_resolver/settings" || return 1
  if ! _contains "$_pfsense_response" '"enablessl":true'; then
    _info "SSL/TLS is not enabled in the DNS Resolver, skipping Unbound"
    return 0
  fi

  _info "Assigning certificate to Unbound and applying"
  _pfsense_call PATCH "/services/dns_resolver/settings" "{\"sslcertref\": \"$_pf_dot_refid\"}" || return 1
  _pfsense_call POST "/services/dns_resolver/apply" "{}" || return 1
  return 0
}
