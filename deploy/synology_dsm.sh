#!/usr/bin/env sh

# Here is a script to deploy cert to Synology DSM
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
# SYNO_DID - device ID to skip OTP - defaults to empty
#
#returns 0 means success, otherwise error.

########  Public functions #####################

_syno_get_cookie_data() {
  grep "\W$1=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o "$1=[^;]*;" | tr -d ';'
}

#domain keyfile certfile cafile fullchain
synology_dsm_deploy() {

  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"

  _debug _cdomain "$_cdomain"

  # Get Username and Password, but don't save until we successfully authenticate
  _getdeployconf SYNO_Username
  _getdeployconf SYNO_Password
  _getdeployconf SYNO_Create
  _getdeployconf SYNO_DID
  if [ -z "$SYNO_Username" ] || [ -z "$SYNO_Password" ]; then
    SYNO_Username=""
    SYNO_Password=""
    _err "SYNO_Username & SYNO_Password must be set"
    return 1
  fi
  _debug2 SYNO_Username "$SYNO_Username"
  _secure_debug2 SYNO_Password "$SYNO_Password"

  # Optional scheme, hostname, and port for Synology DSM
  _getdeployconf SYNO_Scheme
  _getdeployconf SYNO_Hostname
  _getdeployconf SYNO_Port

  # default vaules for scheme, hostname, and port
  # defaulting to localhost and http because it's localhost...
  [ -n "${SYNO_Scheme}" ] || SYNO_Scheme="http"
  [ -n "${SYNO_Hostname}" ] || SYNO_Hostname="localhost"
  [ -n "${SYNO_Port}" ] || SYNO_Port="5000"

  _savedeployconf SYNO_Scheme "$SYNO_Scheme"
  _savedeployconf SYNO_Hostname "$SYNO_Hostname"
  _savedeployconf SYNO_Port "$SYNO_Port"

  _debug2 SYNO_Scheme "$SYNO_Scheme"
  _debug2 SYNO_Hostname "$SYNO_Hostname"
  _debug2 SYNO_Port "$SYNO_Port"

  # Get the certificate description, but don't save it until we verfiy it's real
  _getdeployconf SYNO_Certificate
  if [ -z "${SYNO_Certificate:?}" ]; then
    _err "SYNO_Certificate needs to be defined (with the Certificate description name)"
    return 1
  fi
  _debug SYNO_Certificate "$SYNO_Certificate"

  _base_url="$SYNO_Scheme://$SYNO_Hostname:$SYNO_Port"
  _debug _base_url "$_base_url"

  # Login, get the token from JSON and session id from cookie
  _info "Logging into $SYNO_Hostname:$SYNO_Port"
  response=$(_get "$_base_url/webman/login.cgi?username=$SYNO_Username&passwd=$SYNO_Password&enable_syno_token=yes&device_id=$SYNO_DID")
  token=$(echo "$response" | grep "SynoToken" | sed -n 's/.*"SynoToken" *: *"\([^"]*\).*/\1/p')
  _debug3 response "$response"

  if [ -z "$token" ]; then
    _err "Unable to authenticate to $SYNO_Hostname:$SYNO_Port using $SYNO_Scheme."
    _err "Check your username and password."
    return 1
  fi

  _H1="Cookie: $(_syno_get_cookie_data "id"); $(_syno_get_cookie_data "smid")"
  _H2="X-SYNO-TOKEN: $token"
  export _H1
  export _H2
  _debug2 H1 "${_H1}"
  _debug2 H2 "${_H2}"

  # Now that we know the username and password are good, save them
  _savedeployconf SYNO_Username "$SYNO_Username"
  _savedeployconf SYNO_Password "$SYNO_Password"
  _savedeployconf SYNO_DID "$SYNO_DID"
  _debug token "$token"

  _info "Getting certificates in Synology DSM"
  response=$(_post "api=SYNO.Core.Certificate.CRT&method=list&version=1" "$_base_url/webapi/entry.cgi")
  _debug3 response "$response"
  id=$(echo "$response" | sed -n "s/.*\"desc\":\"$SYNO_Certificate\",\"id\":\"\([^\"]*\).*/\1/p")
  _debug2 id "$id"

  if [ -z "$id" ] && [ -z "${SYNO_Create:?}" ]; then
    _err "Unable to find certificate: $SYNO_Certificate and \$SYNO_Create is not set"
    return 1
  fi

  # we've verified this certificate description is a thing, so save it
  _savedeployconf SYNO_Certificate "$SYNO_Certificate"

  default=false
  if echo "$response" | sed -n "s/.*\"desc\":\"$SYNO_Certificate\",\([^{]*\).*/\1/p" | grep -- 'is_default":true' >/dev/null; then
    default=true
  fi
  _debug2 default "$default"

  _info "Generate form POST request"
  nl="\015\012"
  delim="--------------------------$(_utc_date | tr -d -- '-: ')"
  content="--$delim${nl}Content-Disposition: form-data; name=\"key\"; filename=\"$(basename "$_ckey")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ckey")\012"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"cert\"; filename=\"$(basename "$_ccert")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ccert")\012"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"inter_cert\"; filename=\"$(basename "$_cca")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_cca")\012"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"id\"${nl}${nl}$id"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"desc\"${nl}${nl}${SYNO_Certificate}"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"as_default\"${nl}${nl}${default}"
  content="$content${nl}--$delim--${nl}"
  content="$(printf "%b_" "$content")"
  content="${content%_}" # protect trailing \n

  _info "Upload certificate to the Synology DSM"
  response=$(_post "$content" "$_base_url/webapi/entry.cgi?api=SYNO.Core.Certificate&method=import&version=1&SynoToken=$token" "" "POST" "multipart/form-data; boundary=${delim}")
  _debug3 response "$response"

  if ! echo "$response" | grep '"error":' >/dev/null; then
    if echo "$response" | grep '"restart_httpd":true' >/dev/null; then
      _info "http services were restarted"
    else
      _info "http services were NOT restarted"
    fi
    return 0
  else
    _err "Unable to update certificate, error code $response"
    return 1
  fi
}
