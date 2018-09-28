#!/usr/bin/env sh

#
# Hosteurope API
#
# Author: Peter Postmann
# Report Bugs here: https://github.com/peterpostmann/acme.sh
# --
#
# Pass credentials before "acme.sh --deploy -d example.com --deploy-hook hosteurope ..."
# --
# export DEPLOY_HOSTEUROPE_Username="username"
# export DEPLOY_HOSTEUROPE_Password="password"
# export DEPLOY_HOSTEUROPE_WebServer="wp_id"
# export DEPLOY_HOSTEUROPE_Directory="v_id" (enter 0 for global)
# --

########  Public functions #####################

HOSTEUROPE_Sso="https://sso.hosteurope.de/api/app/v1/login"
HOSTEUROPE_Deploy_Api="https://kis.hosteurope.de/administration/webhosting/admin.php"

#domain keyfile certfile cafile fullchain
hosteurope_deploy() {
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

  # shellcheck disable=SC2154
  if [ -z "$DEPLOY_HOSTEUROPE_Username" ] && [ -n "$HOSTEUROPE_Username" ]; then
    DEPLOY_HOSTEUROPE_Username="$HOSTEUROPE_Username"
  fi

  # shellcheck disable=SC2154
  if [ -z "$DEPLOY_HOSTEUROPE_Password" ] && [ -n "$HOSTEUROPE_Password" ]; then
    DEPLOY_HOSTEUROPE_Password="$HOSTEUROPE_Password"
  fi

  DEPLOY_HOSTEUROPE_Username="${DEPLOY_HOSTEUROPE_Username:-$(_readaccountconf_mutable DEPLOY_HOSTEUROPE_Username)}"
  DEPLOY_HOSTEUROPE_Password="${DEPLOY_HOSTEUROPE_Password:-$(_readaccountconf_mutable DEPLOY_HOSTEUROPE_Password)}"
  DEPLOY_HOSTEUROPE_WebServer="${DEPLOY_HOSTEUROPE_WebServer:-$(_readaccountconf_mutable DEPLOY_HOSTEUROPE_WebServer)}"
  DEPLOY_HOSTEUROPE_Directory="${DEPLOY_HOSTEUROPE_Directory:-$(_readaccountconf_mutable DEPLOY_HOSTEUROPE_Directory)}"
  if [ -z "$DEPLOY_HOSTEUROPE_Username" ] || [ -z "$DEPLOY_HOSTEUROPE_Password" ] || [ -z "$DEPLOY_HOSTEUROPE_WebServer" ] || [ -z "$DEPLOY_HOSTEUROPE_Directory" ]; then
    DEPLOY_HOSTEUROPE_Username=""
    DEPLOY_HOSTEUROPE_Password=""
    DEPLOY_HOSTEUROPE_WebServer=""
    DEPLOY_HOSTEUROPE_Directory=""
    _err "You don't specify hosteurope username, password, webserver and directory."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable DEPLOY_HOSTEUROPE_Username "$DEPLOY_HOSTEUROPE_Username"
  _saveaccountconf_mutable DEPLOY_HOSTEUROPE_Password "$DEPLOY_HOSTEUROPE_Password"
  _saveaccountconf_mutable DEPLOY_HOSTEUROPE_WebServer "$DEPLOY_HOSTEUROPE_WebServer"
  _saveaccountconf_mutable DEPLOY_HOSTEUROPE_Directory "$DEPLOY_HOSTEUROPE_Directory"

  _debug "deploy cert"
  _debug "wp_id" "$DEPLOY_HOSTEUROPE_WebServer"
  _debug "v_id" "$DEPLOY_HOSTEUROPE_Directory"

  _hosteurope_upload "$(cat "$_ccert")" "$(cat "$_ckey")" "$(cat "$_cca")"
}

####################  Private functions below ##################################

_hosteurope_login() {

  _readaccountconf_mutable HOSTEUROPE_Cookie "$HOSTEUROPE_Cookie"
  _readaccountconf_mutable HOSTEUROPE_Expires "$HOSTEUROPE_Expires"

  if [ -n "$HOSTEUROPE_Cookie" ] && [ -n "$HOSTEUROPE_Expires" ] && [ "$HOSTEUROPE_Expires" -gt "$(date "+%s")" ]; then
    return 0
  fi

  # a call to _inithttp is needed to set HTTP_HEADER correctly (see https://github.com/Neilpang/acme.sh/issues/1859)
  _inithttp

  response="$(_post "{\"identifier\":\"$1\",\"password\":\"$2\",\"brandId\":\"b9c8f0f0-60dd-4cab-9da8-512b352d9c1a\"}" "${HOSTEUROPE_Sso}" "" "POST" "application/json")"

  if [ "$response" != '{"success":true}' ]; then
    _err "error $response"
    _debug2 response "$response"
    return 1
  fi

  if ! headers=$(cat "$HTTP_HEADER"); then
    _err "error headers not found"
    _debug2 HTTP_HEADER "$HTTP_HEADER"
    return 1
  fi

  if ! cookies=$(echo "$headers" | sed -n -e 's/^Set-Cookie: //p'); then
    _err "error authidp cookie not found"
    _debug2 headers "$headers"
    _debug2 cookies "$cookies"
    return 1
  fi

  if ! authidp=$(echo "$cookies" | grep "auth_idp="); then
    _err "error authidp cookie not found"
    _debug2 cookies "$cookies"
    return 1
  fi

  if ! HOSTEUROPE_Cookie=$(echo "$cookies" | awk '{print $1}' | tr -d '\n'); then
    _err "error parsing cookie"
    _debug2 cookies "$cookies"
    return 1
  fi

  if ! expires=$(echo "$authidp" | sed -n -e 's/.*Expires=//p' | sed -n -e 's/;.*//p'); then
    _err "error parsing cookie expiration date"
    _debug2 authidp "$authidp"
    return 1
  fi

  HOSTEUROPE_Expires=$(date -d "$expires" "+%s")

  _saveaccountconf_mutable HOSTEUROPE_Cookie "$HOSTEUROPE_Cookie"
  _saveaccountconf_mutable HOSTEUROPE_Expires "$HOSTEUROPE_Expires"

  return 0
}

_hosteurope_upload() {

  wp_id="$(printf '%s' "$DEPLOY_HOSTEUROPE_WebServer" | _url_encode)"
  v_id="$(printf '%s' "$DEPLOY_HOSTEUROPE_Directory" | _url_encode)"

  certfile="$1"
  keyfile="$2"
  cafile="$3"

  _hosteurope_login "$DEPLOY_HOSTEUROPE_Username" "$DEPLOY_HOSTEUROPE_Password"
  _H1="Cookie: $HOSTEUROPE_Cookie"
  _debug2 Cookie "$_H1"

  data="$(printf '
-----------------------------XXX\nContent-Disposition: form-data; name="v_id"\n\n%s
-----------------------------XXX\nContent-Disposition: form-data; name="menu"\n\n6
-----------------------------XXX\nContent-Disposition: form-data; name="mode"\n\nsslupload
-----------------------------XXX\nContent-Disposition: form-data; name="wp_id"\n\n%s
-----------------------------XXX\nContent-Disposition: form-data; name="submode"\n\nsslfileupload
-----------------------------XXX\nContent-Disposition: form-data; name="certfile"; filename="domain.cert"\nContent-Type: application/x-x509-ca-cert\n\n%s\n
-----------------------------XXX\nContent-Disposition: form-data; name="keyfile"; filename="domain.key"\nContent-Type: application/octet-stream\n\n%s\n
-----------------------------XXX\nContent-Disposition: form-data; name="keypass"\n\n\n
-----------------------------XXX\nContent-Disposition: form-data; name="cafile"; filename="ca.cert"\nContent-Type: application/x-x509-ca-cert\n\n%s\n
-----------------------------XXX--' "$v_id" "$wp_id" "$certfile" "$keyfile" "$cafile")"

  if ! response="$(_post "$data" "$HOSTEUROPE_Deploy_Api" "" "POST" "multipart/form-data; boundary=---------------------------XXX")"; then
    _err "error"
    return 1
  fi

  _debug2 response "$response"

  if echo "$response" | grep "<title>KIS Login</title>" >/dev/null; then
    _err "Invalid Credentials"
    return 1
  fi

  if echo "$response" | grep "FEHLER" >/dev/null; then
    _err "$(_hosteurope_result "$response" "FEHLER")"
    return 1
  fi

  if echo "$response" | grep "INFO" >/dev/null; then
    _info "$(_hosteurope_result "$response" "INFO")"
    return 0
  fi

  _err "Unknown response"
  return 1
}

_hosteurope_result() {
  echo "$1" | awk '/INFO/ {for(i=1; i<=10; i++) {getline; print}}' | grep -a "<li>" | sed 's/^\s*<li>//g' | sed 's/<\/li>*$//g'
}
