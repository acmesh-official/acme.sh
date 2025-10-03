#!/bin/bash

################################################################################
# ACME.sh 3rd party deploy plugin for Synology DSM
################################################################################
# Authors: Brian Hartvigsen (creator), https://github.com/tresni
#          Martin Arndt (contributor), https://troublezone.net/
# Updated: 2023-07-03
# Issues:  https://github.com/acmesh-official/acme.sh/issues/2727
################################################################################
# Usage (shown values are the examples):
# 1. Set required environment variables:
# - use automatically created temp admin user to authenticate
#   export SYNO_USE_TEMP_ADMIN=1
# - or provide your own admin user credential to authenticate
#   1. export SYNO_USERNAME="adminUser"
#   2. export SYNO_PASSWORD="adminPassword"
# 2. Set optional environment variables
# - common optional variables
#   - export SYNO_SCHEME="http"         - defaults to "http"
#   - export SYNO_HOSTNAME="localhost"  - defaults to "localhost"
#   - export SYNO_PORT="5000"           - defaults to "5000"
#   - export SYNO_CREATE=1 - to allow creating the cert if it doesn't exist
#   - export SYNO_CERTIFICATE="" - to replace a specific cert by its
#                                    description
# - temp admin optional variables
#   - export SYNO_LOCAL_HOSTNAME=1   - if set to 1, force to treat hostname is
#                                      targeting current local machine (since
#                                      this method only locally supported)
# - exsiting admin 2FA-OTP optional variables
#   - export SYNO_OTP_CODE="XXXXXX" - if set, script won't require to
#                                     interactive input the OTP code
#   - export SYNO_DEVICE_NAME="CertRenewal" - if set, script won't require to
#                                             interactive input the device name
#   - export SYNO_DEVICE_ID=""      - (deprecated, auth with OTP code instead)
#                                     required for omitting 2FA-OTP
# 3. Run command:
# acme.sh --deploy --deploy-hook synology_dsm -d example.com
################################################################################
# Dependencies:
# - curl
# - synouser & synogroup & synosetkeyvalue (Required for SYNO_USE_TEMP_ADMIN=1)
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
  _migratedeployconf SYNO_Username SYNO_USERNAME
  _migratedeployconf SYNO_Password SYNO_PASSWORD
  _migratedeployconf SYNO_Device_ID SYNO_DEVICE_ID
  _migratedeployconf SYNO_Device_Name SYNO_DEVICE_NAME
  _getdeployconf SYNO_USERNAME
  _getdeployconf SYNO_PASSWORD
  _getdeployconf SYNO_DEVICE_ID
  _getdeployconf SYNO_DEVICE_NAME

  # Prepare to use temp admin if SYNO_USE_TEMP_ADMIN is set
  _getdeployconf SYNO_USE_TEMP_ADMIN
  _check2cleardeployconfexp SYNO_USE_TEMP_ADMIN
  _debug2 SYNO_USE_TEMP_ADMIN "$SYNO_USE_TEMP_ADMIN"

  if [ -n "$SYNO_USE_TEMP_ADMIN" ]; then
    if ! _exists synouser || ! _exists synogroup || ! _exists synosetkeyvalue; then
      _err "Missing required tools to creat temp admin user, please set SYNO_USERNAME and SYNO_PASSWORD instead."
      _err "Notice: temp admin user authorization method only supports local deployment on DSM."
      return 1
    fi
    if synouser --help 2>&1 | grep -q 'Permission denied'; then
      _err "For creating temp admin user, the deploy script must be run as root."
      return 1
    fi

    [ -n "$SYNO_USERNAME" ] || _savedeployconf SYNO_USERNAME ""
    [ -n "$SYNO_PASSWORD" ] || _savedeployconf SYNO_PASSWORD ""

    _debug "Setting temp admin user credential..."
    SYNO_USERNAME=sc-acmesh-tmp
    SYNO_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    # Set 2FA-OTP settings to empty consider they won't be needed.
    SYNO_DEVICE_ID=
    SYNO_DEVICE_NAME=
    SYNO_OTP_CODE=
  else
    _debug2 SYNO_USERNAME "$SYNO_USERNAME"
    _secure_debug2 SYNO_PASSWORD "$SYNO_PASSWORD"
    _debug2 SYNO_DEVICE_NAME "$SYNO_DEVICE_NAME"
    _secure_debug2 SYNO_DEVICE_ID "$SYNO_DEVICE_ID"
  fi

  if [ -z "$SYNO_USERNAME" ] || [ -z "$SYNO_PASSWORD" ]; then
    _err "You must set either SYNO_USE_TEMP_ADMIN, or set both SYNO_USERNAME and SYNO_PASSWORD."
    return 1
  fi

  # Optional scheme, hostname and port for Synology DSM
  _migratedeployconf SYNO_Scheme SYNO_SCHEME
  _migratedeployconf SYNO_Hostname SYNO_HOSTNAME
  _migratedeployconf SYNO_Port SYNO_PORT
  _getdeployconf SYNO_SCHEME
  _getdeployconf SYNO_HOSTNAME
  _getdeployconf SYNO_PORT

  # Default values for scheme, hostname and port
  # Defaulting to localhost and http, because it's localhost…
  [ -n "$SYNO_SCHEME" ] || SYNO_SCHEME=http
  [ -n "$SYNO_HOSTNAME" ] || SYNO_HOSTNAME=localhost
  [ -n "$SYNO_PORT" ] || SYNO_PORT=5000
  _savedeployconf SYNO_SCHEME "$SYNO_SCHEME"
  _savedeployconf SYNO_HOSTNAME "$SYNO_HOSTNAME"
  _savedeployconf SYNO_PORT "$SYNO_PORT"
  _debug2 SYNO_SCHEME "$SYNO_SCHEME"
  _debug2 SYNO_HOSTNAME "$SYNO_HOSTNAME"
  _debug2 SYNO_PORT "$SYNO_PORT"

  # Get the certificate description, but don't save it until we verify it's real
  _migratedeployconf SYNO_Certificate SYNO_CERTIFICATE "base64"
  _getdeployconf SYNO_CERTIFICATE
  _check2cleardeployconfexp SYNO_CERTIFICATE
  _debug SYNO_CERTIFICATE "${SYNO_CERTIFICATE:-}"

  # shellcheck disable=SC1003 # We are not trying to escape a single quote
  if printf "%s" "$SYNO_CERTIFICATE" | grep '\\'; then
    _err "Do not use a backslash (\) in your certificate description"
    return 1
  fi

  _debug "Getting API version..."
  _base_url="$SYNO_SCHEME://$SYNO_HOSTNAME:$SYNO_PORT"
  _debug _base_url "$_base_url"
  response=$(_get "$_base_url/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query&query=SYNO.API.Auth")
  api_path=$(echo "$response" | grep "SYNO.API.Auth" | sed -n 's/.*"path" *: *"\([^"]*\)".*/\1/p')
  api_version=$(echo "$response" | grep "SYNO.API.Auth" | sed -n 's/.*"maxVersion" *: *\([0-9]*\).*/\1/p')
  _debug3 response "$response"
  _debug3 api_path "$api_path"
  _debug3 api_version "$api_version"

  # Login, get the session ID and SynoToken from JSON
  _info "Logging into $SYNO_HOSTNAME:$SYNO_PORT..."
  encoded_username="$(printf "%s" "$SYNO_USERNAME" | _url_encode)"
  encoded_password="$(printf "%s" "$SYNO_PASSWORD" | _url_encode)"

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

    if [ -z "$SYNO_DEVICE_ID" ]; then
      _getdeployconf SYNO_DID
      [ -n "$SYNO_DID" ] || SYNO_DEVICE_ID="$SYNO_DID"
    fi
    if [ -n "$SYNO_DEVICE_ID" ]; then
      _H1="Cookie: did=$SYNO_DEVICE_ID"
      export _H1
      _debug3 H1 "${_H1}"
    fi

    response=$(_post "method=login&account=$encoded_username&passwd=$encoded_password&api=SYNO.API.Auth&version=$api_version&enable_syno_token=yes&otp_code=$DEPRECATED_otp_code&device_name=certrenewal&device_id=$SYNO_DEVICE_ID" "$_base_url/webapi/$api_path?enable_syno_token=yes")
    _debug3 response "$response"
  # ## END ## - DEPRECATED, for backward compatibility
  # If SYNO_DEVICE_ID or SYNO_OTP_CODE is set, we treat current account enabled 2FA-OTP.
  # Notice that if SYNO_USE_TEMP_ADMIN=1, both variables will be unset
  else
    if [ -n "$SYNO_DEVICE_ID" ] || [ -n "$SYNO_OTP_CODE" ]; then
      response='{"error":{"code":403}}'
    # Assume the current account disabled 2FA-OTP, try to log in right away.
    else
      if [ -n "$SYNO_USE_TEMP_ADMIN" ]; then
        _getdeployconf SYNO_LOCAL_HOSTNAME
        _debug SYNO_LOCAL_HOSTNAME "${SYNO_LOCAL_HOSTNAME:-}"
        if [ "$SYNO_HOSTNAME" != "localhost" ] && [ "$SYNO_HOSTNAME" != "127.0.0.1" ]; then
          if [ "$SYNO_LOCAL_HOSTNAME" != "1" ]; then
            _err "SYNO_USE_TEMP_ADMIN=1 only support local deployment, though if you are sure that the hostname $SYNO_HOSTNAME is targeting to your **current local machine**, execute 'export SYNO_LOCAL_HOSTNAME=1' then rerun."
            return 1
          fi
        fi
        _debug "Creating temp admin user in Synology DSM..."
        if synogroup --help | grep -q '\-\-memberadd '; then
          _temp_admin_create "$SYNO_USERNAME" "$SYNO_PASSWORD"
          synogroup --memberadd administrators "$SYNO_USERNAME" >/dev/null
        elif synogroup --help | grep -q '\-\-member '; then
          # For supporting DSM 6.x which only has `--member` parameter.
          cur_admins=$(synogroup --get administrators | awk -F '[][]' '/Group Members/,0{if(NF>1)printf "%s ", $2}')
          if [ -n "$cur_admins" ]; then
            _temp_admin_create "$SYNO_USERNAME" "$SYNO_PASSWORD"
            _secure_debug3 admin_users "$cur_admins$SYNO_USERNAME"
            # shellcheck disable=SC2086
            synogroup --member administrators $cur_admins $SYNO_USERNAME >/dev/null
          else
            _err "The tool synogroup may be broken, please set SYNO_USERNAME and SYNO_PASSWORD instead."
            return 1
          fi
        else
          _err "Unsupported synogroup tool detected, please set SYNO_USERNAME and SYNO_PASSWORD instead."
          return 1
        fi
        # havig a workaround to temporary disable enforce 2FA-OTP, will restore
        # it soon (after a single request), though if any accident occurs like
        # unexpected interruption, this setting can be easily reverted manually.
        otp_enforce_option=$(synogetkeyvalue /etc/synoinfo.conf otp_enforce_option)
        if [ -n "$otp_enforce_option" ] && [ "${otp_enforce_option:-"none"}" != "none" ]; then
          synosetkeyvalue /etc/synoinfo.conf otp_enforce_option none
          _info "Enforcing 2FA-OTP has been disabled to complete temp admin authentication."
          _info "Notice: it will be restored soon, if not, you can restore it manually via Control Panel."
          _info "previous_otp_enforce_option" "$otp_enforce_option"
        else
          otp_enforce_option=""
        fi
      fi
      response=$(_get "$_base_url/webapi/$api_path?api=SYNO.API.Auth&version=$api_version&method=login&format=sid&account=$encoded_username&passwd=$encoded_password&enable_syno_token=yes")
      if [ -n "$SYNO_USE_TEMP_ADMIN" ] && [ -n "$otp_enforce_option" ]; then
        synosetkeyvalue /etc/synoinfo.conf otp_enforce_option "$otp_enforce_option"
        _info "Restored previous enforce 2FA-OTP option."
      fi
      _debug3 response "$response"
    fi
  fi

  error_code=$(echo "$response" | grep '"error":' | grep -o '"code":[0-9]*' | grep -o '[0-9]*')
  _debug2 error_code "$error_code"
  # Account has 2FA-OTP enabled, since error 403 reported.
  # https://global.download.synology.com/download/Document/Software/DeveloperGuide/Os/DSM/All/enu/DSM_Login_Web_API_Guide_enu.pdf
  if [ "$error_code" == "403" ]; then
    if [ -z "$SYNO_DEVICE_NAME" ]; then
      printf "Enter device name or leave empty for default (CertRenewal): "
      read -r SYNO_DEVICE_NAME
      [ -n "$SYNO_DEVICE_NAME" ] || SYNO_DEVICE_NAME="CertRenewal"
    fi

    if [ -n "$SYNO_DEVICE_ID" ]; then
      # Omit OTP code with SYNO_DEVICE_ID.
      response=$(_get "$_base_url/webapi/$api_path?api=SYNO.API.Auth&version=$api_version&method=login&format=sid&account=$encoded_username&passwd=$encoded_password&enable_syno_token=yes&device_name=$SYNO_DEVICE_NAME&device_id=$SYNO_DEVICE_ID")
      _secure_debug3 response "$response"
    else
      # Require the OTP code if still unset.
      if [ -z "$SYNO_OTP_CODE" ]; then
        printf "Enter OTP code for user '%s': " "$SYNO_USERNAME"
        read -r SYNO_OTP_CODE
      fi
      _secure_debug SYNO_OTP_CODE "${SYNO_OTP_CODE:-}"

      if [ -z "$SYNO_OTP_CODE" ]; then
        response='{"error":{"code":404}}'
      else
        response=$(_get "$_base_url/webapi/$api_path?api=SYNO.API.Auth&version=$api_version&method=login&format=sid&account=$encoded_username&passwd=$encoded_password&enable_syno_token=yes&enable_device_token=yes&device_name=$SYNO_DEVICE_NAME&otp_code=$SYNO_OTP_CODE")
        _secure_debug3 response "$response"

        id_property='device_id'
        [ "${api_version}" -gt '6' ] || id_property='did'
        SYNO_DEVICE_ID=$(echo "$response" | grep "$id_property" | sed -n 's/.*"'$id_property'" *: *"\([^"]*\).*/\1/p')
        _secure_debug2 SYNO_DEVICE_ID "$SYNO_DEVICE_ID"
      fi
    fi
    error_code=$(echo "$response" | grep '"error":' | grep -o '"code":[0-9]*' | grep -o '[0-9]*')
    _debug2 error_code "$error_code"
  fi

  if [ -n "$error_code" ]; then
    if [ "$error_code" == "403" ] && [ -n "$SYNO_DEVICE_ID" ]; then
      _cleardeployconf SYNO_DEVICE_ID
      _err "Failed to authenticate with SYNO_DEVICE_ID (may expired or invalid), please try again in a new terminal window."
    elif [ "$error_code" == "404" ]; then
      _err "Failed to authenticate with provided 2FA-OTP code, please try again in a new terminal window."
    elif [ "$error_code" == "406" ]; then
      if [ -n "$SYNO_USE_TEMP_ADMIN" ]; then
        _err "Failed with unexcepted error, please report this by providing full log with '--debug 3'."
      else
        _err "Enforce auth with 2FA-OTP enabled, please configure the user to enable 2FA-OTP to continue."
      fi
    elif [ "$error_code" == "400" ]; then
      _err "Failed to authenticate, no such account or incorrect password."
    elif [ "$error_code" == "401" ]; then
      _err "Failed to authenticate with a non-existent account."
    elif [ "$error_code" == "408" ] || [ "$error_code" == "409" ] || [ "$error_code" == "410" ]; then
      _err "Failed to authenticate, the account password has expired or must be changed."
    else
      _err "Failed to authenticate with error: $error_code."
    fi
    _temp_admin_cleanup "$SYNO_USE_TEMP_ADMIN" "$SYNO_USERNAME"
    return 1
  fi

  sid=$(echo "$response" | grep "sid" | sed -n 's/.*"sid" *: *"\([^"]*\).*/\1/p')
  token=$(echo "$response" | grep "synotoken" | sed -n 's/.*"synotoken" *: *"\([^"]*\).*/\1/p')
  _debug "Session ID" "$sid"
  _debug SynoToken "$token"
  if [ -z "$sid" ] || [ -z "$token" ]; then
    # Still can't get necessary info even got no errors, may Synology have API updated?
    _err "Unable to authenticate to $_base_url, you may report this by providing full log with '--debug 3'."
    _temp_admin_cleanup "$SYNO_USE_TEMP_ADMIN" "$SYNO_USERNAME"
    return 1
  fi

  _H1="X-SYNO-TOKEN: $token"
  export _H1
  _debug2 H1 "${_H1}"

  # Now that we know the username and password are good, save them if not in temp admin mode.
  if [ -n "$SYNO_USE_TEMP_ADMIN" ]; then
    _cleardeployconf SYNO_USERNAME
    _cleardeployconf SYNO_PASSWORD
    _cleardeployconf SYNO_DEVICE_ID
    _cleardeployconf SYNO_DEVICE_NAME
    _savedeployconf SYNO_USE_TEMP_ADMIN "$SYNO_USE_TEMP_ADMIN"
    _savedeployconf SYNO_LOCAL_HOSTNAME "$SYNO_LOCAL_HOSTNAME"
  else
    _savedeployconf SYNO_USERNAME "$SYNO_USERNAME"
    _savedeployconf SYNO_PASSWORD "$SYNO_PASSWORD"
    _savedeployconf SYNO_DEVICE_ID "$SYNO_DEVICE_ID"
    _savedeployconf SYNO_DEVICE_NAME "$SYNO_DEVICE_NAME"
  fi

  _info "Getting certificates in Synology DSM..."
  response=$(_post "api=SYNO.Core.Certificate.CRT&method=list&version=1&_sid=$sid" "$_base_url/webapi/entry.cgi")
  _debug3 response "$response"
  escaped_certificate="$(printf "%s" "$SYNO_CERTIFICATE" | sed 's/\([].*^$[]\)/\\\1/g;s/"/\\\\"/g')"
  _debug escaped_certificate "$escaped_certificate"
  id=$(echo "$response" | sed -n "s/.*\"desc\":\"$escaped_certificate\",\"id\":\"\([^\"]*\).*/\1/p")
  _debug2 id "$id"

  error_code=$(echo "$response" | grep '"error":' | grep -o '"code":[0-9]*' | grep -o '[0-9]*')
  _debug2 error_code "$error_code"
  if [ -n "$error_code" ]; then
    if [ "$error_code" -eq 105 ]; then
      _err "Current user is not administrator and does not have sufficient permission for deploying."
    else
      _err "Failed to fetch certificate info: $error_code, please try again or contact Synology to learn more."
    fi
    _temp_admin_cleanup "$SYNO_USE_TEMP_ADMIN" "$SYNO_USERNAME"
    return 1
  fi

  _migratedeployconf SYNO_Create SYNO_CREATE
  _getdeployconf SYNO_CREATE
  _debug2 SYNO_CREATE "$SYNO_CREATE"

  if [ -z "$id" ] && [ -z "$SYNO_CREATE" ]; then
    _err "Unable to find certificate: $SYNO_CERTIFICATE and $SYNO_CREATE is not set."
    _temp_admin_cleanup "$SYNO_USE_TEMP_ADMIN" "$SYNO_USERNAME"
    return 1
  fi

  # We've verified this certificate description is a thing, so save it
  _savedeployconf SYNO_CERTIFICATE "$SYNO_CERTIFICATE" "base64"

  _info "Generating form POST request..."
  nl="\0015\0012"
  delim="--------------------------$(_utc_date | tr -d -- '-: ')"
  content="--$delim${nl}Content-Disposition: form-data; name=\"key\"; filename=\"$(basename "$_ckey")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ckey")\0012"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"cert\"; filename=\"$(basename "$_ccert")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ccert")\0012"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"inter_cert\"; filename=\"$(basename "$_cca")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_cca")\0012"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"id\"${nl}${nl}$id"
  content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"desc\"${nl}${nl}${SYNO_CERTIFICATE}"
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
    _temp_admin_cleanup "$SYNO_USE_TEMP_ADMIN" "$SYNO_USERNAME"
    _logout
    return 0
  else
    _temp_admin_cleanup "$SYNO_USE_TEMP_ADMIN" "$SYNO_USERNAME"
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

_temp_admin_create() {
  _username="$1"
  _password="$2"
  synouser --del "$_username" >/dev/null 2>/dev/null
  synouser --add "$_username" "$_password" "" 0 "" 0 >/dev/null
}

_temp_admin_cleanup() {
  _flag=$1
  _username=$2

  if [ -n "${_flag}" ]; then
    _debug "Cleanuping temp admin info..."
    synouser --del "$_username" >/dev/null
  fi
}

#_cleardeployconf   key
_cleardeployconf() {
  _cleardomainconf "SAVED_$1"
}

# key
_check2cleardeployconfexp() {
  _key="$1"
  _clear_key="CLEAR_$_key"
  # Clear saved settings if explicitly requested
  if [ -n "$(eval echo \$"$_clear_key")" ]; then
    _debug2 "$_key: value cleared from config, exported value will be ignored."
    _cleardeployconf "$_key"
    eval "$_key"=
    export "$_key"=
    eval SAVED_"$_key"=
    export SAVED_"$_key"=
  fi
}
