#!/bin/bash

################################################################################
# ACME.sh 3rd party deploy plugin for Synology DSM
################################################################################
# Authors: Brian Hartvigsen (creator), https://github.com/tresni
#          Martin Arndt (contributor), https://troublezone.net/
# Updated: 2023-07-03
# Issues:  https://github.com/acmesh-official/acme.sh/issues/2727
################################################################################
# Usage:
# 1. Set required environment variables (two ways):
# - Create temp admin user automatically:
#   export SYNO_USE_TEMP_ADMIN=1
# - Or provide your own admin user credential:
#   1. export SYNO_Username="adminUser"
#   2. export SYNO_Password="adminPassword"
# 2. Set optional environment variables (shown values are the defaults):
# - export SYNO_Certificate="" - to replace a specific certificate via description
# - export SYNO_Scheme="http"
# - export SYNO_Hostname="localhost"
# - export SYNO_Port="5000"
# - export SYNO_Create=1   - to allow creating the certificate if it doesn't exist
# - export SYNO_Device_Name="CertRenewal" - required if 2FA-OTP enabled
# - export SYNO_Device_ID=""              - required for skipping 2FA-OTP
# 3. Run command:
# acme.sh --deploy --deploy-hook synology_dsm -d example.com
################################################################################
# Dependencies:
# - jq & curl
# - synouser & synogroup (When available and SYNO_USE_TEMP_ADMIN is set)
################################################################################
# Return value:
# 0 means success, otherwise error.
################################################################################

########## Public functions ####################################################
#domain keyfile certfile cafile fullchain
synology_dsm_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"

  _debug _cdomain "$_cdomain"

  # Get username & password, but don't save until we authenticated successfully
  _getdeployconf SYNO_USE_TEMP_ADMIN
  _getdeployconf SYNO_Username
  _getdeployconf SYNO_Password
  _getdeployconf SYNO_Create
  _getdeployconf SYNO_DID
  _getdeployconf SYNO_TOTP_SECRET
  _getdeployconf SYNO_Device_Name
  _getdeployconf SYNO_Device_ID

  # Prepare temp admin user info if SYNO_USE_TEMP_ADMIN is set
  if [ -n "${SYNO_USE_TEMP_ADMIN:-}" ]; then
    if ! _exists synouser; then
      if ! _exists synogroup; then
        _err "Tools are missing for creating temp admin user, please set SYNO_Username & SYNO_Password instead."
        return 1
      fi
    fi
    _debug "Setting temp admin user credential..."
    SYNO_Username=sc-acmesh-tmp
    SYNO_Password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    # Ignore 2FA-OTP settings which won't be needed.
    SYNO_Device_Name=
    SYNO_Device_ID=
  fi

  if [ -z "${SYNO_Username:-}" ] || [ -z "${SYNO_Password:-}" ]; then
    _err "You must set either SYNO_USE_TEMP_ADMIN, or set both SYNO_Username and SYNO_Password."
    return 1
  fi
  _debug2 SYNO_Username "$SYNO_Username"
  _secure_debug2 SYNO_Password "$SYNO_Password"
  _debug2 SYNO_Create "$SYNO_Create"
  _debug2 SYNO_Device_Name "$SYNO_Device_Name"
  _secure_debug2 SYNO_Device_ID "$SYNO_Device_ID"

  # Optional scheme, hostname & port for Synology DSM
  _getdeployconf SYNO_Scheme
  _getdeployconf SYNO_Hostname
  _getdeployconf SYNO_Port

  # Default values for scheme, hostname & port
  # Defaulting to localhost & http, because it's localhost…
  [ -n "${SYNO_Scheme}" ] || SYNO_Scheme="http"
  [ -n "${SYNO_Hostname}" ] || SYNO_Hostname="localhost"
  [ -n "${SYNO_Port}" ] || SYNO_Port="5000"
  _savedeployconf SYNO_USE_TEMP_ADMIN "$SYNO_USE_TEMP_ADMIN"
  _savedeployconf SYNO_Scheme "$SYNO_Scheme"
  _savedeployconf SYNO_Hostname "$SYNO_Hostname"
  _savedeployconf SYNO_Port "$SYNO_Port"
  _debug2 SYNO_Scheme "$SYNO_Scheme"
  _debug2 SYNO_Hostname "$SYNO_Hostname"
  _debug2 SYNO_Port "$SYNO_Port"

  # Get the certificate description, but don't save it until we verify it's real
  _getdeployconf SYNO_Certificate
  _debug SYNO_Certificate "${SYNO_Certificate:-}"

  # shellcheck disable=SC1003 # We are not trying to escape a single quote
  if printf "%s" "$SYNO_Certificate" | grep '\\'; then
    _err "Do not use a backslash (\) in your certificate description"
    return 1
  fi

  _base_url="$SYNO_Scheme://$SYNO_Hostname:$SYNO_Port"
  _debug _base_url "$_base_url"

  _debug "Getting API version"
  response=$(_get "$_base_url/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query&query=SYNO.API.Auth")
  api_path=$(echo "$response" | grep "SYNO.API.Auth" | sed -n 's/.*"path" *: *"\([^"]*\)".*/\1/p')
  api_version=$(echo "$response" | grep "SYNO.API.Auth" | sed -n 's/.*"maxVersion" *: *\([0-9]*\).*/\1/p')
  _debug3 response "$response"
  _debug3 api_path "$api_path"
  _debug3 api_version "$api_version"

  # Login, get the session ID & SynoToken from JSON
  _info "Logging into $SYNO_Hostname:$SYNO_Port"
  encoded_username="$(printf "%s" "$SYNO_Username" | _url_encode)"
  encoded_password="$(printf "%s" "$SYNO_Password" | _url_encode)"

  otp_code=""
  # START - DEPRECATED, only kept for legacy compatibility reasons
  if [ -n "$SYNO_TOTP_SECRET" ]; then
    _info "WARNING: Usage of SYNO_TOTP_SECRET is deprecated!"
    _info "         See synology_dsm.sh script or ACME.sh Wiki page for details:"
    _info "         https://github.com/acmesh-official/acme.sh/wiki/Synology-NAS-Guide"
    if ! _exists oathtool; then
      _err "oathtool could not be found, install oathtool to use SYNO_TOTP_SECRET"
      return 1
    fi
    DEPRECATED_otp_code="$(oathtool --base32 --totp "${SYNO_TOTP_SECRET}" 2>/dev/null)"

    if [ -n "$SYNO_DID" ]; then
      _H1="Cookie: did=$SYNO_DID"
      export _H1
      _debug3 H1 "${_H1}"
    fi

    response=$(_post "method=login&account=$encoded_username&passwd=$encoded_password&api=SYNO.API.Auth&version=$api_version&enable_syno_token=yes&otp_code=$DEPRECATED_otp_code&device_name=certrenewal&device_id=$SYNO_DID" "$_base_url/webapi/auth.cgi?enable_syno_token=yes")
    _debug3 response "$response"
  # END - DEPRECATED, only kept for legacy compatibility reasons
  # If SYNO_DeviceDevice_ID & SYNO_Device_Name both empty, just log in normally
  elif [ -z "${SYNO_Device_ID:-}" ] && [ -z "${SYNO_Device_Name:-}" ]; then
    if [ -n "$SYNO_USE_TEMP_ADMIN" ]; then
      _debug "Creating temp admin user in Synology DSM"
      synouser --del "$SYNO_Username" >/dev/null 2>/dev/null
      synouser --add "$SYNO_Username" "$SYNO_Password" "" 0 "" 0 >/dev/null
      synogroup --memberadd administrators "$SYNO_Username" >/dev/null
    fi
    response=$(_get "$_base_url/webapi/entry.cgi?api=SYNO.API.Auth&version=$api_version&method=login&format=sid&account=$encoded_username&passwd=$encoded_password&enable_syno_token=yes")
    _debug3 response "$response"
  # Get device ID if still empty first, otherwise log in right away
  # If SYNO_Device_Name is set, we treat that account enabled two-factor authorization, consider SYNO_Device_ID is not set, so it won't be able to login without requiring the OTP code.
  elif [ -n "${SYNO_Device_Name:-}" ] && [ -z "${SYNO_Device_ID:-}" ]; then
    printf "Enter OTP code for user '%s': " "$SYNO_Username"
    read -r otp_code
    response=$(_get "$_base_url/webapi/$api_path?api=SYNO.API.Auth&version=$api_version&method=login&format=sid&account=$encoded_username&passwd=$encoded_password&otp_code=$otp_code&enable_syno_token=yes&enable_device_token=yes&device_name=$SYNO_Device_Name")
    _secure_debug3 response "$response"

    id_property='device_id'
    [ "${api_version}" -gt '6' ] || id_property='did'
    SYNO_Device_ID=$(echo "$response" | grep "$id_property" | sed -n 's/.*"'$id_property'" *: *"\([^"]*\).*/\1/p')
    _secure_debug2 SYNO_Device_ID "$SYNO_Device_ID"
  # Otherwise, if SYNO_Device_ID is set, we can just use it to login.
  else
    if [ -z "${SYNO_Device_Name:-}" ]; then
      printf "Enter device name or leave empty for default (CertRenewal): "
      read -r SYNO_Device_Name
      [ -n "${SYNO_Device_Name}" ] || SYNO_Device_Name="CertRenewal"
    fi
    response=$(_get "$_base_url/webapi/$api_path?api=SYNO.API.Auth&version=$api_version&method=login&format=sid&account=$encoded_username&passwd=$encoded_password&enable_syno_token=yes&device_name=$SYNO_Device_Name&device_id=$SYNO_Device_ID")
    _secure_debug3 response "$response"
  fi

  sid=$(echo "$response" | grep "sid" | sed -n 's/.*"sid" *: *"\([^"]*\).*/\1/p')
  token=$(echo "$response" | grep "synotoken" | sed -n 's/.*"synotoken" *: *"\([^"]*\).*/\1/p')
  _debug "Session ID" "$sid"
  _debug SynoToken "$token"
  if [ -z "$sid" ] || [ -z "$token" ]; then
    _err "Unable to authenticate to $_base_url - check your username & password."
    _err "If two-factor authentication is enabled for the user:"
    _err "- set SYNO_Device_Name then input *correct* OTP-code manually"
    _err "- get & set SYNO_Device_ID via your browser cookies"
    _remove_temp_admin "$SYNO_USE_TEMP_ADMIN" "$SYNO_Username"
    return 1
  fi

  _H1="X-SYNO-TOKEN: $token"
  export _H1
  _debug2 H1 "${_H1}"

  # Now that we know the username & password are good, save them
  _savedeployconf SYNO_Username "$SYNO_Username"
  _savedeployconf SYNO_Password "$SYNO_Password"
  if [ -z "${SYNO_USE_TEMP_ADMIN:-}" ]; then
    _savedeployconf SYNO_Device_Name "$SYNO_Device_Name"
    _savedeployconf SYNO_Device_ID "$SYNO_Device_ID"
  fi

  _info "Getting certificates in Synology DSM"
  response=$(_post "api=SYNO.Core.Certificate.CRT&method=list&version=1&_sid=$sid" "$_base_url/webapi/entry.cgi")
  _debug3 response "$response"
  escaped_certificate="$(printf "%s" "$SYNO_Certificate" | sed 's/\([].*^$[]\)/\\\1/g;s/"/\\\\"/g')"
  _debug escaped_certificate "$escaped_certificate"
  id=$(echo "$response" | sed -n "s/.*\"desc\":\"$escaped_certificate\",\"id\":\"\([^\"]*\).*/\1/p")
  _debug2 id "$id"

  if [ -z "$id" ] && [ -z "${SYNO_Create:-}" ]; then
    _err "Unable to find certificate: $SYNO_Certificate & \$SYNO_Create is not set"
    _remove_temp_admin "$SYNO_USE_TEMP_ADMIN" "$SYNO_Username"
    return 1
  fi

  # We've verified this certificate description is a thing, so save it
  _savedeployconf SYNO_Certificate "$SYNO_Certificate" "base64"

  _info "Generate form POST request"
  nl="\0015\0012"
  delim="--------------------------$(_utc_date | tr -d -- '-: ')"
  content="--$delim${nl}Content-Disposition: form-data; name=\"key\"; filename=\"$(basename "$_ckey")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ckey")\0012"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"cert\"; filename=\"$(basename "$_ccert")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ccert")\0012"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"inter_cert\"; filename=\"$(basename "$_cca")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_cca")\0012"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"id\"${nl}${nl}$id"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"desc\"${nl}${nl}${SYNO_Certificate}"
  if echo "$response" | sed -n "s/.*\"desc\":\"$escaped_certificate\",\([^{]*\).*/\1/p" | grep -- 'is_default":true' >/dev/null; then
    _debug2 default "This is the default certificate"
    content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"as_default\"${nl}${nl}true"
  else
    _debug2 default "This is NOT the default certificate"
  fi
  content="$content${nl}--$delim--${nl}"
  content="$(printf "%b_" "$content")"
  content="${content%_}" # protect trailing \n

  _info "Upload certificate to the Synology DSM"
  response=$(_post "$content" "$_base_url/webapi/entry.cgi?api=SYNO.Core.Certificate&method=import&version=1&SynoToken=$token&_sid=$sid" "" "POST" "multipart/form-data; boundary=${delim}")
  _debug3 response "$response"

  if ! echo "$response" | grep '"error":' >/dev/null; then
    if echo "$response" | grep '"restart_httpd":true' >/dev/null; then
      _info "Restarting HTTP services succeeded"
    else
      _info "Restarting HTTP services failed"
    fi
    _remove_temp_admin "$SYNO_USE_TEMP_ADMIN" "$SYNO_Username"
    _logout
    return 0
  else
    _remove_temp_admin "$SYNO_USE_TEMP_ADMIN" "$SYNO_Username"
    _err "Unable to update certificate, error code $response"
    _logout
    return 1
  fi
}

####################  Private functions below ##################################
_logout() {
  # Logout CERT user only to not occupy a permanent session, e.g. in DSM's "Connected Users" widget (based on previous variables)
  response=$(_get "$_base_url/webapi/$api_path?api=SYNO.API.Auth&version=$api_version&method=logout&_sid=$sid")
  _debug3 response "$response"
}

_remove_temp_admin() {
  flag=$1
  username=$2

  if [ -n "${flag}" ]; then
    _debug "Removing temp admin user in Synology DSM"
    synouser --del "$username" >/dev/null
  fi
}
