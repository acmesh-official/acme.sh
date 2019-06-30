#!/usr/bin/env sh

# Here is a script to deploy cert to Synology DSM vault
# (https://www.vaultproject.io/)
#
# it requires the jq and curl are in the $PATH and the following
# environment variables must be set:
#
# SYNO_Username - Synology Username to login (must be an administrator)
# SYNO_Password - Synology Password to login
# SYNO_Certificate - Certificate description to target for replacement
#
# The following environmental variables may be set if you don't like their
# default values:
#
# SYNO_Scheme - defaults to http
# SYNO_Hostname - defaults to localhost
# SYNO_Port - defaults to 5000
#
#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
synology_dsm_deploy() {

  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"

  _debug _cdomain "$_cdomain"

  # Get Username and Password, but don't save until we successfully authenticate
  SYNO_Username="${SYNO_Username:-$(_readaccountconf_mutable SYNO_Username)}"
  SYNO_Password="${SYNO_Password:-$(_readaccountconf_mutable SYNO_Password)}"
  if [ -z "$SYNO_Username" ] || [ -z "$SYNO_Password" ]; then
    SYNO_Username=""
    SYNO_Password=""
    _err "SYNO_Username & SYNO_Password must be set"
    return 1
  fi
  _debug2 SYNO_Username "$SYNO_Username"
  _secure_debug2 SYNO_Password "$SYNO_Password"

  # Optional scheme, hostname, and port for Synology DSM
  SYNO_Scheme="${SYNO_Scheme:-$(_readaccountconf_mutable SYNO_Scheme)}"
  SYNO_Hostname="${SYNO_Hostname:-$(_readaccountconf_mutable SYNO_Hostname)}"
  SYNO_Port="${SYNO_Port:-$(_readaccountconf_mutable SYNO_Port)}"
  _saveaccountconf_mutable SYNO_Scheme "$SYNO_Scheme"
  _saveaccountconf_mutable SYNO_Hostname "$SYNO_Hostname"
  _saveaccountconf_mutable SYNO_Port "$SYNO_Port"

  # default vaules for scheme, hostname, and port
  # defaulting to localhost and http because it's localhost...
  [ -n "${SYNO_Scheme}" ] || SYNO_Scheme="http"
  [ -n "${SYNO_Hostname}" ] || SYNO_Hostname="localhost"
  [ -n "${SYNO_Port}" ] || SYNO_Port="5000"

  _debug2 SYNO_Scheme "$SYNO_Scheme"
  _debug2 SYNO_Hostname "$SYNO_Hostname"
  _debug2 SYNO_Port "$SYNO_Port"

  # Get the certificate description, but don't save it until we verfiy it's real
  _getdeployconf SYNO_Certificate
  # shellcheck disable=SC2154
  if [ -z "${SYNO_Certificate}" ]; then
    _err "SYNO_Certificate needs to be defined (with the Certificate description name)"
    return 1
  fi
  _debug SYNO_Certificate "$SYNO_Certificate"

  # We can't use _get or _post because they lack support for cookies
  # use jq because I'm too lazy to figure out what is required to parse json
  # by hand.  Also it seems to be in place for Synology DSM (6.2.1 at least)
  for x in curl jq; do
    if ! _exists "$x"; then
      _err "Please install $x first."
      _err "We need $x to work."
      return 1
    fi
  done

  _base_url="$SYNO_Scheme://$SYNO_Hostname:$SYNO_Port"
  _debug _base_url "$_base_url"

  _cookie_jar="$(_mktemp)"
  _debug _cookie_jar "$_cookie_jar"

  # Login, get the token from JSON and session id from cookie
  _debug "Logging into $SYNO_Hostname:$SYNO_Port"
  token=$(curl -sk -c "$_cookie_jar" "$_base_url/webman/login.cgi?username=$SYNO_Username&passwd=$SYNO_Password&enable_syno_token=yes" | jq -r .SynoToken)
  if [ "$token" = "null" ]; then
    _err "Unable to authenticate to $SYNO_Hostname:$SYNO_Port using $SYNO_Scheme."
    _err "Check your username and password."
    rm "$_cookie_jar"
    return 1
  fi

  # Now that we know the username and password are good, save them
  _saveaccountconf_mutable SYNO_Username "$SYNO_Username"
  _saveaccountconf_mutable SYNO_Password "$SYNO_Password"
  _secure_debug2 token "$token"

  # Use token and session id to get the list of certificates
  response=$(curl -sk -b "$_cookie_jar" "$_base_url/webapi/entry.cgi" -H "X-SYNO-TOKEN: $token" -d api=SYNO.Core.Certificate.CRT -d method=list -d version=1)
  _debug3 response "$response"
  # select the first certificate matching our description
  cert=$(echo "$response" | jq -r ".data.certificates | map(select(.desc == \"$SYNO_Certificate\"))[0]")
  _debug3 cert "$cert"

  if [ "$cert" = "null" ]; then
    _err "Unable to find certificate: $SYNO_Certificate"
    rm "$_cookie_jar"
    return 1
  fi

  # we've verified this certificate description is a thing, so save it
  _savedeployconf SYNO_Certificate "$SYNO_Certificate"

  id=$(echo "$cert" | jq -r ".id")
  default=$(echo "$cert" | jq -r ".is_default")
  _debug2 id "$id"
  _debug2 default "$default"

  # This is the heavy lifting, make the API call to update a certificate in place
  response=$(curl -sk -b "$_cookie_jar" "$_base_url/webapi/entry.cgi?api=SYNO.Core.Certificate&method=import&version=1&SynoToken=$token" -F "key=@$_ckey" -F "cert=@$_ccert" -F "inter_cert=@$_cca" -F "id=$id" -F "desc=$SYNO_Certificate" -F "as_default=$default")
  _debug3 response "$response"
  success=$(echo "$response" | jq -r ".success")
  _debug2 success "$success"
  rm "$_cookie_jar"

  if [ "$success" = "true" ]; then
    restarted=$(echo "$response" | jq -r ".data.restart_httpd")
    if [ "$restarted" = "true" ]; then
      _info "http services were restarted"
    else
      _info "http services were NOT restarted"
    fi
    return 0
  else
    code=$(echo "$response" | jq -r ".error.code")
    _err "Unable to update certificate, error code $code"
    return 1
  fi
}
