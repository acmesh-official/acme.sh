#!/usr/bin/env sh

# Script to deploy cert to Peplink Routers
#
# The following environment variables must be set:
#
# PEPLINK_Hostname - Peplink hostname
# PEPLINK_Username - Peplink username to login
# PEPLINK_Password - Peplink password to login
#
# The following environmental variables may be set if you don't like their
# default values:
#
# PEPLINK_Certtype - Certificate type to target for replacement
#                    defaults to "webadmin", can be one of:
#                      * "chub" (ContentHub)
#                      * "openvpn" (OpenVPN CA)
#                      * "portal" (Captive Portal SSL)
#                      * "webadmin" (Web Admin SSL)
#                      * "webproxy" (Proxy Root CA)
#                      * "wwan_ca" (Wi-Fi WAN CA)
#                      * "wwan_client" (Wi-Fi WAN Client)
# PEPLINK_Scheme   - defaults to "https"
# PEPLINK_Port     - defaults to "443"
#
#returns 0 means success, otherwise error.

########  Public functions #####################

_peplink_get_cookie_data() {
  grep -i "\W$1=" | grep -i "^Set-Cookie:" | _tail_n 1 | _egrep_o "$1=[^;]*;" | tr -d ';'
}

#domain keyfile certfile cafile fullchain
peplink_deploy() {

  _cdomain="$1"
  _ckey="$2"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _cfullchain "$_cfullchain"
  _debug _ckey "$_ckey"

  # Get Hostname, Username and Password, but don't save until we successfully authenticate
  _getdeployconf PEPLINK_Hostname
  _getdeployconf PEPLINK_Username
  _getdeployconf PEPLINK_Password
  if [ -z "${PEPLINK_Hostname:-}" ] || [ -z "${PEPLINK_Username:-}" ] || [ -z "${PEPLINK_Password:-}" ]; then
    _err "PEPLINK_Hostname & PEPLINK_Username & PEPLINK_Password must be set"
    return 1
  fi
  _debug2 PEPLINK_Hostname "$PEPLINK_Hostname"
  _debug2 PEPLINK_Username "$PEPLINK_Username"
  _secure_debug2 PEPLINK_Password "$PEPLINK_Password"

  # Optional certificate type, scheme, and port for Peplink
  _getdeployconf PEPLINK_Certtype
  _getdeployconf PEPLINK_Scheme
  _getdeployconf PEPLINK_Port

  # Don't save the certificate type until we verify it exists and is supported
  _savedeployconf PEPLINK_Scheme "$PEPLINK_Scheme"
  _savedeployconf PEPLINK_Port "$PEPLINK_Port"

  # Default vaules for certificate type, scheme, and port
  [ -n "${PEPLINK_Certtype}" ] || PEPLINK_Certtype="webadmin"
  [ -n "${PEPLINK_Scheme}" ] || PEPLINK_Scheme="https"
  [ -n "${PEPLINK_Port}" ] || PEPLINK_Port="443"

  _debug2 PEPLINK_Certtype "$PEPLINK_Certtype"
  _debug2 PEPLINK_Scheme "$PEPLINK_Scheme"
  _debug2 PEPLINK_Port "$PEPLINK_Port"

  _base_url="$PEPLINK_Scheme://$PEPLINK_Hostname:$PEPLINK_Port"
  _debug _base_url "$_base_url"

  # Login, get the auth token from the cookie
  _info "Logging into $PEPLINK_Hostname:$PEPLINK_Port"
  encoded_username="$(printf "%s" "$PEPLINK_Username" | _url_encode)"
  encoded_password="$(printf "%s" "$PEPLINK_Password" | _url_encode)"
  response=$(_post "func=login&username=$encoded_username&password=$encoded_password" "$_base_url/cgi-bin/MANGA/api.cgi")
  auth_token=$(_peplink_get_cookie_data "bauth" <"$HTTP_HEADER")
  _debug3 response "$response"
  _debug auth_token "$auth_token"

  if [ -z "$auth_token" ]; then
    _err "Unable to authenticate to $PEPLINK_Hostname:$PEPLINK_Port using $PEPLINK_Scheme."
    _err "Check your username and password."
    return 1
  fi

  _H1="Cookie: $auth_token"
  export _H1
  _debug2 H1 "${_H1}"

  # Now that we know the hostnameusername and password are good, save them
  _savedeployconf PEPLINK_Hostname "$PEPLINK_Hostname"
  _savedeployconf PEPLINK_Username "$PEPLINK_Username"
  _savedeployconf PEPLINK_Password "$PEPLINK_Password"

  _info "Generate form POST request"

  encoded_key="$(_url_encode <"$_ckey")"
  encoded_fullchain="$(_url_encode <"$_cfullchain")"
  body="cert_type=$PEPLINK_Certtype&cert_uid=&section=CERT_modify&key_pem=$encoded_key&key_pem_passphrase=&key_pem_passphrase_confirm=&cert_pem=$encoded_fullchain"
  _debug3 body "$body"

  _info "Upload $PEPLINK_Certtype certificate to the Peplink"

  response=$(_post "$body" "$_base_url/cgi-bin/MANGA/admin.cgi")
  _debug3 response "$response"

  if echo "$response" | grep 'Success' >/dev/null; then
    # We've verified this certificate type is valid, so save it
    _savedeployconf PEPLINK_Certtype "$PEPLINK_Certtype"
    _info "Certificate was updated"
    return 0
  else
    _err "Unable to update certificate, error code $response"
    return 1
  fi
}
