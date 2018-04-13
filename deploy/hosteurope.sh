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

  if [ -z "$DEPLOY_HOSTEUROPE_Username" ] && [ ! -z "$HOSTEUROPE_Username" ]; then
    DEPLOY_HOSTEUROPE_Username="$HOSTEUROPE_Username"
  fi

  if [ -z "$DEPLOY_HOSTEUROPE_Password" ] && ! [ -z "$HOSTEUROPE_Password" ]; then
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
  _saveaccountconf_mutable DEPLOY_HOSTEUROPE_Username  "$DEPLOY_HOSTEUROPE_Username"
  _saveaccountconf_mutable DEPLOY_HOSTEUROPE_Password  "$DEPLOY_HOSTEUROPE_Password"
  _saveaccountconf_mutable DEPLOY_HOSTEUROPE_WebServer "$DEPLOY_HOSTEUROPE_WebServer"
  _saveaccountconf_mutable DEPLOY_HOSTEUROPE_Directory "$DEPLOY_HOSTEUROPE_Directory"

  _debug "deploy cert"
  _debug "wp_id" "$DEPLOY_HOSTEUROPE_WebServer"
  _debug "v_id"  "$DEPLOY_HOSTEUROPE_Directory"

  _hosteurope_upload "$DEPLOY_HOSTEUROPE_Username" "$DEPLOY_HOSTEUROPE_Password" "$DEPLOY_HOSTEUROPE_WebServer" "$DEPLOY_HOSTEUROPE_Directory" "$(cat "$_ccert")" "$(cat "$_ckey")" "$(cat "$_cca")"
}

####################  Private functions below ##################################

_hosteurope_upload() {

  kdnummer="$(printf '%s' "$1" | _url_encode)"
  passwd="$(printf '%s' "$2" | _url_encode)"
  wp_id="$(printf '%s' "$3" | _url_encode)"
  v_id="$(printf '%s' "$4" | _url_encode)"
  certfile="$5"
  keyfile="$6" 
  cafile="$7"

  url="$HOSTEUROPE_Deploy_Api?kdnummer=$kdnummer&passwd=$passwd"

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
  _debug2 data

  if ! response="$(_post "$data" "$url" "" "POST" "multipart/form-data; boundary=---------------------------XXX")"; then
    _err "error"
    return 1
  fi

  _debug2 response "$response"

  if echo "$response" | grep "<title>KIS Login</title>" > /dev/null; then
    _err "Invalid Credentials"
    return 1
  fi

  if echo "$response" | grep "FEHLER" > /dev/null; then
    _err "$(_hosteurope_result "$response" "FEHLER")"
    return 1
  fi

  if echo "$response" | grep "INFO" > /dev/null; then
    _info "$(_hosteurope_result "$response" "INFO")"
    return 0
  fi

  _err "Unknown response"
  return 1
}

_hosteurope_result() {
    echo "$1" |  grep -a -A 10 "$2" | grep -a "<li>" | sed 's/^\s*<li>//g' | sed 's/<\/li>*$//g'
}