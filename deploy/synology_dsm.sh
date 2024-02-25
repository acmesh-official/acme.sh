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
# 1. Set required environment variables:
# - use automatically created temp admin user to authenticate
#   `export SYNO_UseTempAdmin=1`
# - or provide your own admin user credential to authenticate
#   1. `export SYNO_Username="adminUser"`
#   2. `export SYNO_Password="adminPassword"`
# 2. Set optional environment variables (shown values are the defaults)
# - common optional variables
#   - `export SYNO_Scheme="http"`
#   - `export SYNO_Hostname="localhost"`
#   - `export SYNO_Port="5000"`
#   - `export SYNO_Create=1` - to allow creating the cert if it doesn't exist
#   - `export SYNO_Certificate=""` - to replace a specific cert by its
#                                    description
# - 2FA-OTP optional variables (with your own admin user)
#   - `export SYNO_DeviceName=""`  - required for 2FA-OTP, script won't require
#                                    interactive input the device name if set.
#   - `export SYNO_OTPCode=""`     - required for 2FA-OTP, script won't require
#                                    interactive input the code if set.
#   - `export SYNO_DeviceID=""`    - required for omitting 2FA-OTP (might be
#                                    deprecated, auth with OTP code instead)
# 3. Run command:
# `acme.sh --deploy --deploy-hook synology_dsm -d example.com``
################################################################################
# Dependencies:
# - curl
# - synouser & synogroup (When available and SYNO_UseTempAdmin is set)
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

  # Get username and password, but don't save until we authenticated successfully
  _getdeployconf SYNO_Username
  _getdeployconf SYNO_Password
  _getdeployconf SYNO_DeviceID
  _getdeployconf SYNO_DeviceName

  # ## START ## - DEPRECATED, for backward compatibility
  _getdeployconf SYNO_Device_ID
  _getdeployconf SYNO_Device_Name
  [ -n "$SYNO_DeviceID" ] || SYNO_DeviceID="${SYNO_Device_ID:-}"
  [ -n "$SYNO_DeviceName" ] || SYNO_DeviceName="${SYNO_Device_Name:-}"
  # ## END ## - DEPRECATED, for backward compatibility

  # Prepare to use temp admin if SYNO_UseTempAdmin is set
  _getdeployconf SYNO_UseTempAdmin
  _debug2 SYNO_UseTempAdmin "$SYNO_UseTempAdmin"

  # Back to use existing admin user if explicitly requested
  if [ "$SYNO_UseTempAdmin" == "0" ]; then
    _debug2 "Back to use existing user rather than temp admin user."
    SYNO_UseTempAdmin=""
  fi

  if [ -n "$SYNO_UseTempAdmin" ]; then
    if ! _exists synouser || ! _exists synogroup; then
      _err "Tools are missing for creating temp admin user, please set SYNO_Username and SYNO_Password instead."
      return 1
    fi

    [ -n "$SYNO_Username" ] || _savedeployconf SYNO_Username ""
    [ -n "$SYNO_Password" ] || _savedeployconf SYNO_Password ""

    _debug "Setting temp admin user credential..."
    SYNO_Username=sc-acmesh-tmp
    SYNO_Password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    # Set 2FA-OTP settings to empty consider they won't be needed.
    SYNO_DeviceID=
    SYNO_DeviceName=
    SYNO_OTPCode=
    # Pre-delete temp admin user if already exists.
    synouser --del "$SYNO_Username" >/dev/null 2>/dev/null
  else
    _debug2 SYNO_Username "$SYNO_Username"
    _secure_debug2 SYNO_Password "$SYNO_Password"
    _debug2 SYNO_DeviceName "$SYNO_DeviceName"
    _secure_debug2 SYNO_DeviceID "$SYNO_DeviceID"
  fi

  if [ -z "$SYNO_Username" ] || [ -z "$SYNO_Password" ]; then
    _err "You must set either SYNO_UseTempAdmin, or set both SYNO_Username and SYNO_Password."
    return 1
  fi

  # Optional scheme, hostname and port for Synology DSM
  _getdeployconf SYNO_Scheme
  _getdeployconf SYNO_Hostname
  _getdeployconf SYNO_Port

  # Default values for scheme, hostname and port
  # Defaulting to localhost and http, because it's localhost…
  [ -n "$SYNO_Scheme" ] || SYNO_Scheme="http"
  [ -n "$SYNO_Hostname" ] || SYNO_Hostname="localhost"
  [ -n "$SYNO_Port" ] || SYNO_Port="5000"
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

  _debug "Getting API version..."
  _base_url="$SYNO_Scheme://$SYNO_Hostname:$SYNO_Port"
  _debug _base_url "$_base_url"
  response=$(_get "$_base_url/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query&query=SYNO.API.Auth")
  api_path=$(echo "$response" | grep "SYNO.API.Auth" | sed -n 's/.*"path" *: *"\([^"]*\)".*/\1/p')
  api_version=$(echo "$response" | grep "SYNO.API.Auth" | sed -n 's/.*"maxVersion" *: *\([0-9]*\).*/\1/p')
  _debug3 response "$response"
  _debug3 api_path "$api_path"
  _debug3 api_version "$api_version"

  # Login, get the session ID and SynoToken from JSON
  _info "Logging into $SYNO_Hostname:$SYNO_Port..."
  encoded_username="$(printf "%s" "$SYNO_Username" | _url_encode)"
  encoded_password="$(printf "%s" "$SYNO_Password" | _url_encode)"

  # ## START ## - DEPRECATED, for backward compatibility
  _getdeployconf SYNO_TOTP_SECRET

  if [ -n "$SYNO_TOTP_SECRET" ]; then
    _info "WARNING: Usage of SYNO_TOTP_SECRET is deprecated!"
    _info "         See synology_dsm.sh script or ACME.sh Wiki page for details:"
    _info "         https://github.com/acmesh-official/acme.sh/wiki/Synology-NAS-Guide"
    if ! _exists oathtool; then
      _err "oathtool could not be found, install oathtool to use SYNO_TOTP_SECRET"
      return 1
    fi
    DEPRECATED_otp_code="$(oathtool --base32 --totp "$SYNO_TOTP_SECRET" 2>/dev/null)"

    if [ -z "$SYNO_DeviceID" ]; then
      _getdeployconf SYNO_DID
      [ -n "$SYNO_DID" ] || SYNO_DeviceID="$SYNO_DID"
    fi
    if [ -n "$SYNO_DeviceID" ]; then
      _H1="Cookie: did=$SYNO_DeviceID"
      export _H1
      _debug3 H1 "${_H1}"
    fi

    response=$(_post "method=login&account=$encoded_username&passwd=$encoded_password&api=SYNO.API.Auth&version=$api_version&enable_syno_token=yes&otp_code=$DEPRECATED_otp_code&device_name=certrenewal&device_id=$SYNO_DeviceID" "$_base_url/webapi/auth.cgi?enable_syno_token=yes")
    _debug3 response "$response"
  # ## END ## - DEPRECATED, for backward compatibility
  # If SYNO_DeviceID or SYNO_OTPCode is set, we treat current account enabled 2FA-OTP.
  # Notice that if SYNO_UseTempAdmin=1, both variables will be unset
  else
    if [ -n "$SYNO_DeviceID" ] || [ -n "$SYNO_OTPCode" ]; then
      response='{"error":{"code":403}}'
    # Assume the current account disabled 2FA-OTP, try to log in right away.
    else
      if [ -n "$SYNO_UseTempAdmin" ]; then
        _debug "Creating temp admin user in Synology DSM..."
        synouser --add "$SYNO_Username" "$SYNO_Password" "" 0 "scruelt@hotmail.com" 0 >/dev/null
        if synogroup --help | grep -q '\-\-memberadd'; then
          synogroup --memberadd administrators "$SYNO_Username" >/dev/null
        else
          # For supporting DSM 6.x which only has `--member` parameter.
          cur_admins=$(synogroup --get administrators | awk -F '[][]' '/Group Members/,0{if(NF>1)printf "%s ", $2}')
          _secure_debug3 admin_users "$cur_admins$SYNO_Username"
          # shellcheck disable=SC2086
          synogroup --member administrators $cur_admins $SYNO_Username >/dev/null
        fi
        # havig a workaround to temporary disable enforce 2FA-OTP
        otp_enforce_option=$(synogetkeyvalue /etc/synoinfo.conf otp_enforce_option)
        if [ -n "$otp_enforce_option" ] && [ "${otp_enforce_option:-"none"}" != "none" ]; then
          synosetkeyvalue /etc/synoinfo.conf otp_enforce_option none
          _info "Temporary disabled enforce 2FA-OTP to complete authentication."
          _info "previous_otp_enforce_option" "$otp_enforce_option"

        else
          otp_enforce_option=""
        fi
      fi
      response=$(_get "$_base_url/webapi/entry.cgi?api=SYNO.API.Auth&version=$api_version&method=login&format=sid&account=$encoded_username&passwd=$encoded_password&enable_syno_token=yes")
      if [ -n "$SYNO_UseTempAdmin" ] && [ -n "$otp_enforce_option" ]; then
        synosetkeyvalue /etc/synoinfo.conf otp_enforce_option "$otp_enforce_option"
        _info "Restored previous enforce 2FA-OTP option."
      fi
      _debug3 response "$response"
    fi
  fi

  error_code=$(echo "$response" | grep '"error"' | grep -oP '(?<="code":)\d+')
  # Account has 2FA-OTP enabled, since error 403 reported.
  # https://global.download.synology.com/download/Document/Software/DeveloperGuide/Firmware/DSM/All/enu/Synology_DiskStation_Administration_CLI_Guide.pdf
  if [ "$error_code" == "403" ]; then
    if [ -z "$SYNO_DeviceName" ]; then
      printf "Enter device name or leave empty for default (CertRenewal): "
      read -r SYNO_DeviceName
      [ -n "$SYNO_DeviceName" ] || SYNO_DeviceName="CertRenewal"
    fi

    if [ -n "$SYNO_DeviceID" ]; then
      # Omit OTP code with SYNO_DeviceID.
      response=$(_get "$_base_url/webapi/$api_path?api=SYNO.API.Auth&version=$api_version&method=login&format=sid&account=$encoded_username&passwd=$encoded_password&enable_syno_token=yes&device_name=$SYNO_DeviceName&device_id=$SYNO_DeviceID")
      _secure_debug3 response "$response"
    else
      # Require the OTP code if still unset.
      if [ -z "$SYNO_OTPCode" ]; then
        printf "Enter OTP code for user '%s': " "$SYNO_Username"
        read -r SYNO_OTPCode
      fi

      if [ -z "$SYNO_OTPCode" ]; then
        response='{"error":{"code":404}}'
      else
        response=$(_get "$_base_url/webapi/$api_path?api=SYNO.API.Auth&version=$api_version&method=login&format=sid&account=$encoded_username&passwd=$encoded_password&enable_syno_token=yes&enable_device_token=yes&device_name=$SYNO_DeviceName&otp_code=$SYNO_OTPCode")
        _secure_debug3 response "$response"

        id_property='device_id'
        [ "${api_version}" -gt '6' ] || id_property='did'
        SYNO_DeviceID=$(echo "$response" | grep "$id_property" | sed -n 's/.*"'$id_property'" *: *"\([^"]*\).*/\1/p')
        _secure_debug2 SYNO_DeviceID "$SYNO_DeviceID"
      fi
    fi
    error_code=$(echo "$response" | grep '"error"' | grep -oP '(?<="code":)\d+')
  fi

  if [ -n "$error_code" ]; then
    if [ "$error_code" == "403" ] && [ -n "$SYNO_DeviceID" ]; then
      _savedeployconf SYNO_DeviceID ""
      _err "Failed to authenticate with SYNO_DeviceID (may expired or invalid), please try again in a new terminal window."
    elif [ "$error_code" == "404" ]; then
      _err "Failed to authenticate with provided 2FA-OTP code, please try again in a new terminal window."
    elif [ "$error_code" == "406" ]; then
      if [ -n "$SYNO_UseTempAdmin" ]; then
        _err "SYNO_UseTempAdmin=1 is not supported if enforce auth with 2FA-OTP is enabled."
      else
        _err "Enforce auth with 2FA-OTP enabled, please configure the user to enable 2FA-OTP to continue."
      fi
    elif [ "$error_code" == "400" ] || [ "$error_code" == "401" ] || [ "$error_code" == "408" ] || [ "$error_code" == "409" ] || [ "$error_code" == "410" ]; then
      _err "Failed to authenticate with a non-existent or disabled account, or the account password is incorrect or has expired."
    else
      _err "Failed to authenticate with error: $error_code."
    fi
    _temp_admin_cleanup "$SYNO_UseTempAdmin" "$SYNO_Username"
    return 1
  fi

  sid=$(echo "$response" | grep "sid" | sed -n 's/.*"sid" *: *"\([^"]*\).*/\1/p')
  token=$(echo "$response" | grep "synotoken" | sed -n 's/.*"synotoken" *: *"\([^"]*\).*/\1/p')
  _debug "Session ID" "$sid"
  _debug SynoToken "$token"
  if [ -z "$sid" ] || [ -z "$token" ]; then
    # Still can't get necessary info even got no errors, may Synology have API updated?
    _err "Unable to authenticate to $_base_url, you may report the full log to the community."
    _temp_admin_cleanup "$SYNO_UseTempAdmin" "$SYNO_Username"
    return 1
  fi

  _H1="X-SYNO-TOKEN: $token"
  export _H1
  _debug2 H1 "${_H1}"

  # Now that we know the username and password are good, save them if not in temp admin mode.
  if [ -n "$SYNO_UseTempAdmin" ]; then
    _savedeployconf SYNO_Username ""
    _savedeployconf SYNO_Password ""
    _savedeployconf SYNO_UseTempAdmin "$SYNO_UseTempAdmin"
  else
    _savedeployconf SYNO_Username "$SYNO_Username"
    _savedeployconf SYNO_Password "$SYNO_Password"
  fi
  _savedeployconf SYNO_DeviceID "$SYNO_DeviceID"
  _savedeployconf SYNO_DeviceName "$SYNO_DeviceName"

  _info "Getting certificates in Synology DSM..."
  response=$(_post "api=SYNO.Core.Certificate.CRT&method=list&version=1&_sid=$sid" "$_base_url/webapi/entry.cgi")
  _debug3 response "$response"
  escaped_certificate="$(printf "%s" "$SYNO_Certificate" | sed 's/\([].*^$[]\)/\\\1/g;s/"/\\\\"/g')"
  _debug escaped_certificate "$escaped_certificate"
  id=$(echo "$response" | sed -n "s/.*\"desc\":\"$escaped_certificate\",\"id\":\"\([^\"]*\).*/\1/p")
  _debug2 id "$id"

  error_code=$(echo "$response" | grep '"error"' | grep -oP '(?<="code":)\d+')
  if [ -n "$error_code" ]; then
    if [ "$error_code" -eq 105 ]; then
      _err "Current user is not administrator and does not have sufficient permission for deploying."
    else
      _err "Failed to fetch certificate info with error: $error_code, contact Synology for more info about it."
    fi
    _temp_admin_cleanup "$SYNO_UseTempAdmin" "$SYNO_Username"
    return 1
  fi

  _getdeployconf SYNO_Create
  _debug2 SYNO_Create "$SYNO_Create"
  [ -n "$SYNO_Create" ] || SYNO_Create=1

  if [ -z "$id" ] && [ -z "$SYNO_Create" ]; then
    _err "Unable to find certificate: $SYNO_Certificate and $SYNO_Create is not set."
    _temp_admin_cleanup "$SYNO_UseTempAdmin" "$SYNO_Username"
    return 1
  fi

  # We've verified this certificate description is a thing, so save it
  _savedeployconf SYNO_Certificate "$SYNO_Certificate" "base64"

  _info "Generating form POST request..."
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

  _info "Upload certificate to the Synology DSM."
  response=$(_post "$content" "$_base_url/webapi/entry.cgi?api=SYNO.Core.Certificate&method=import&version=1&SynoToken=$token&_sid=$sid" "" "POST" "multipart/form-data; boundary=${delim}")
  _debug3 response "$response"

  if ! echo "$response" | grep '"error":' >/dev/null; then
    if echo "$response" | grep '"restart_httpd":true' >/dev/null; then
      _info "Restart HTTP services succeeded."
    else
      _info "Restart HTTP services failed."
    fi
    _temp_admin_cleanup "$SYNO_UseTempAdmin" "$SYNO_Username"
    _logout
    return 0
  else
    _temp_admin_cleanup "$SYNO_UseTempAdmin" "$SYNO_Username"
    _err "Unable to update certificate, got error response: $response."
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

_temp_admin_cleanup() {
  flag=$1
  username=$2

  if [ -n "${flag}" ]; then
    _debug "Cleanuping temp admin info..."
    synouser --del "$username" >/dev/null
  fi
}
