#!/usr/bin/env sh

# Deploy certificates to Zyxel GS1900 series switches
#
# This script uses the https web administration interface in order
# to upload updated certificates to Zyxel GS1900 series switches.
# Only a few models have been tested but untested switches from the
# same model line may work as well. If you test and confirm a switch
# as working please submit a pull request updating this compatibility
# list!
#
# Known Issues:
#   1. This is a consumer grade switch and is a bit underpowered
#      the longer the RSA key size the slower your switch web UI
#      will be. RSA 2048 will work, RSA 4096 will work but you may
#      experience performance problems.
#   2. You must use RSA certificates. The switch will reject EC-256
#      and EC-384 certificates in firmware 2.80
#      See: https://community.zyxel.com/en/discussion/21506/bug-cannot-import-ssl-cert-on-gs1900-8-and-gs1900-24e-firmware-v2-80/
#
# Current GS1900 Switch Compatibility:
#   GS1900-8    - Working as of firmware V2.80
#   GS1900-8HP  - Untested
#   GS1900-10HP - Untested
#   GS1900-16   - Untested
#   GS1900-24   - Untested
#   GS1900-24E  - Working as of firmware V2.80
#   GS1900-24EP - Untested
#   GS1900-24HP - Untested
#   GS1900-48   - Untested
#   GS1900-48HP - Untested
#
# Prerequisite Setup Steps:
#   1. Install at least firmware V2.80 on your switch
#   2. Enable HTTPS web management on your switch
#
# Usage:
#   1. Ensure the switch has firmware V2.80 or later.
#   2. Ensure the switch has HTTPS management enabled.
#   3. Set the appropriate environment variables for your environment.
#
#      DEPLOY_ZYXEL_SWITCH          - The switch hostname. (Default: _cdomain)
#      DEPLOY_ZYXEL_SWITCH_USER     - The webadmin user. (Default: admin)
#      DEPLOY_ZYXEL_SWITCH_PASSWORD - The webadmin password for the switch.
#      DEPLOY_ZYXEL_SWITCH_REBOOT   - If "1" reboot after update. (Default: "0")
#
#   4. Run the deployment plugin:
#      acme.sh --deploy --deploy-hook zyxel_gs1900 -d example.com
#
# returns 0 means success, otherwise error.

#domain keyfile certfile cafile fullchain
zyxel_gs1900_deploy() {
  _zyxel_gs1900_minimum_firmware_version="v2.80"

  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug2 _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  _getdeployconf DEPLOY_ZYXEL_SWITCH
  _getdeployconf DEPLOY_ZYXEL_SWITCH_USER
  _getdeployconf DEPLOY_ZYXEL_SWITCH_PASSWORD
  _getdeployconf DEPLOY_ZYXEL_SWITCH_REBOOT

  if [ -z "$DEPLOY_ZYXEL_SWITCH" ]; then
    DEPLOY_ZYXEL_SWITCH="$_cdomain"
  fi

  if [ -z "$DEPLOY_ZYXEL_SWITCH_USER" ]; then
    DEPLOY_ZYXEL_SWITCH_USER="admin"
  fi

  if [ -z "$DEPLOY_ZYXEL_SWITCH_PASSWORD" ]; then
    DEPLOY_ZYXEL_SWITCH_PASSWORD="1234"
  fi

  if [ -z "$DEPLOY_ZYXEL_SWITCH_REBOOT" ]; then
    DEPLOY_ZYXEL_SWITCH_REBOOT="0"
  fi

  _savedeployconf DEPLOY_ZYXEL_SWITCH "$DEPLOY_ZYXEL_SWITCH"
  _savedeployconf DEPLOY_ZYXEL_SWITCH_USER "$DEPLOY_ZYXEL_SWITCH_USER"
  _savedeployconf DEPLOY_ZYXEL_SWITCH_PASSWORD "$DEPLOY_ZYXEL_SWITCH_PASSWORD"
  _savedeployconf DEPLOY_ZYXEL_SWITCH_REBOOT "$DEPLOY_ZYXEL_SWITCH_REBOOT"

  _debug DEPLOY_ZYXEL_SWITCH "$DEPLOY_ZYXEL_SWITCH"
  _debug DEPLOY_ZYXEL_SWITCH_USER "$DEPLOY_ZYXEL_SWITCH_USER"
  _secure_debug DEPLOY_ZYXEL_SWITCH_PASSWORD "$DEPLOY_ZYXEL_SWITCH_PASSWORD"
  _debug DEPLOY_ZYXEL_SWITCH_REBOOT "$DEPLOY_ZYXEL_SWITCH_REBOOT"

  _zyxel_switch_base_uri="https://${DEPLOY_ZYXEL_SWITCH}"

  _info "Beginning to deploy to a Zyxel GS1900 series switch at ${_zyxel_switch_base_uri}."
  _zyxel_gs1900_deployment_precheck || return $?

  _zyxel_gs1900_should_update
  if [ "$?" != "0" ]; then
    _info "The switch already has our certificate installed. No update required."
    return 0
  else
    _info "The switch does not yet have our certificate installed."
  fi

  _info "Logging into the switch web interface."
  _zyxel_gs1900_login || return $?

  _info "Validating the switch is compatible with this deployment process."
  _zyxel_gs1900_validate_device_compatibility || return $?

  _info "Uploading the certificate."
  _zyxel_gs1900_upload_certificate || return $?

  if [ "$DEPLOY_ZYXEL_SWITCH_REBOOT" = "1" ]; then
    _info "Rebooting the switch."
    _zyxel_gs1900_trigger_reboot || return $?
  fi

  return 0
}

_zyxel_gs1900_deployment_precheck() {
  # Initialize the keylength if it isn't already
  if [ -z "$Le_Keylength" ]; then
    Le_Keylength=""
  fi

  if _isEccKey "$Le_Keylength"; then
    _info "Warning: Zyxel GS1900 switches are not currently known to work with ECC keys!"
    _info "You can continue, but your switch may reject your key."
  elif [ -n "$Le_Keylength" ] && [ "$Le_Keylength" -gt "2048" ]; then
    _info "Warning: Your RSA key length is greater than 2048!"
    _info "You can continue, but you may experience performance issues in the web administration interface."
  fi

  # Check the server for some common failure modes prior to authentication and certificate upload in order to avoid
  # sending a certificate when we may not want to.
  test_login_response=$(_post "username=test&password=test&login=true;" "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi?cmd=0.html" '' "POST" "application/x-www-form-urlencoded" 2>&1)
  test_login_page_exitcode="$?"
  _debug3 "Test Login Response: ${test_login_response}"
  if [ "$test_login_page_exitcode" -ne "0" ]; then
    if { [ "${ACME_USE_WGET:-0}" = "0" ] && [ "$test_login_page_exitcode" = "60" ]; } || { [ "${ACME_USE_WGET:-0}" = "1" ] && [ "$test_login_page_exitcode" = "5" ]; }; then
      _err "The SSL certificate at $_zyxel_switch_base_uri could not be validated."
      _err "Please double check your hostname, port, and that you are actually connecting to your switch."
      _err "If the problem persists then please ensure that the certificate is not self-signed, has not"
      _err "expired, and matches the switch hostname. If you expect validation to fail then you can disable"
      _err "certificate validation by running with --insecure."
      return 1
    elif [ "${ACME_USE_WGET:-0}" = "0" ] && [ "$test_login_page_exitcode" = "56" ]; then
      _debug3 "Intentionally ignore curl exit code 56 in our precheck"
    else
      _err "Failed to submit the initial login attempt to $_zyxel_switch_base_uri."
      return 1
    fi
  fi
}

_zyxel_gs1900_login() {
  # Login to the switch and set the appropriate auth cookie in _H1
  username_encoded=$(printf "%s" "$DEPLOY_ZYXEL_SWITCH_USER" | _url_encode)
  password_encoded=$(_zyxel_gs1900_password_obfuscate "$DEPLOY_ZYXEL_SWITCH_PASSWORD" | _url_encode)

  login_response=$(_post "username=${username_encoded}&password=${password_encoded}&login=true;" "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi?cmd=0.html" '' "POST" "application/x-www-form-urlencoded" | tr -d '\n')
  auth_response=$(_post "authId=${login_response}&login_chk=true" "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi?cmd=0.html" '' "POST" "application/x-www-form-urlencoded" | tr -d '\n')
  if [ "$auth_response" != "OK" ]; then
    _err "Login failed due to invalid credentials."
    _err "Please double check the configured username and password and try again."
    return 1
  fi

  sessionid=$(grep -i '^set-cookie:' "$HTTP_HEADER" | _egrep_o 'HTTPS_XSSID=[^;]*;' | tr -d ';')
  _secure_debug2 "sessionid" "$sessionid"

  export _H1="Cookie: $sessionid"
  _secure_debug2 "_H1" "$_H1"

  return 0
}

_zyxel_gs1900_validate_device_compatibility() {
  # Check the switches model and firmware version and throw errors
  # if this script isn't compatible.
  device_info_html=$(_get "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi?cmd=12" | tr -d '\n')

  model_name=$(_zyxel_gs1900_get_model "$device_info_html")
  _debug2 "model_name" "$model_name"
  if [ -z "$model_name" ]; then
    _err "Could not find the switch model name."
    _err "Please re-run with --debug and report a bug."
    return $?
  fi

  if ! expr "$model_name" : "GS1900-" >/dev/null; then
    _err "Switch is an unsupported model: $model_name"
    return 1
  fi

  firmware_version=$(_zyxel_gs1900_get_firmware_version "$device_info_html")
  _debug2 "firmware_version" "$firmware_version"
  if [ -z "$firmware_version" ]; then
    _err "Could not find the switch firmware version."
    _err "Please re-run with --debug and report a bug."
    return $?
  fi

  _debug2 "_zyxel_gs1900_minimum_firmware_version" "$_zyxel_gs1900_minimum_firmware_version"
  minimum_major_version=$(_zyxel_gs1900_parse_major_version "$_zyxel_gs1900_minimum_firmware_version")
  _debug2 "minimum_major_version" "$minimum_major_version"
  minimum_minor_version=$(_zyxel_gs1900_parse_minor_version "$_zyxel_gs1900_minimum_firmware_version")
  _debug2 "minimum_minor_version" "$minimum_minor_version"

  _debug2 "firmware_version" "$firmware_version"
  firmware_major_version=$(_zyxel_gs1900_parse_major_version "$firmware_version")
  _debug2 "firmware_major_version" "$firmware_major_version"
  firmware_minor_version=$(_zyxel_gs1900_parse_minor_version "$firmware_version")
  _debug2 "firmware_minor_version" "$firmware_minor_version"

  _ret=0
  if [ "$firmware_major_version" -lt "$minimum_major_version" ]; then
    _ret=1
  elif [ "$firmware_major_version" -eq "$minimum_major_version" ] && [ "$firmware_minor_version" -lt "$minimum_minor_version" ]; then
    _ret=1
  fi

  if [ "$_ret" != "0" ]; then
    _err "Unsupported firmware version $firmware_version. Please upgrade to at least version $_zyxel_gs1900_minimum_firmware_version."
  fi

  return $?
}

_zyxel_gs1900_should_update() {
  # Get the remote certificate serial number
  _remote_cert=$(${ACME_OPENSSL_BIN:-openssl} s_client -showcerts -connect "${DEPLOY_ZYXEL_SWITCH}:443" 2>/dev/null </dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p')
  _debug3 "_remote_cert" "$_remote_cert"

  _remote_cert_serial=$(printf "%s" "${_remote_cert}" | ${ACME_OPENSSL_BIN:-openssl} x509 -noout -serial)
  _debug2 "_remote_cert_serial" "$_remote_cert_serial"

  # Get our certificate serial number
  _our_cert_serial=$(${ACME_OPENSSL_BIN:-openssl} x509 -noout -serial <"${_ccert}")
  _debug2 "_our_cert_serial" "$_our_cert_serial"

  [ "${_remote_cert_serial}" != "${_our_cert_serial}" ]
}

_zyxel_gs1900_upload_certificate() {
  # Generate a PKCS12 certificate with a temporary password since the web interface
  # requires a password be present. Then upload that certificate.
  temp_cert_password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 64)
  _secure_debug2 "temp_cert_password" "$temp_cert_password"

  temp_pkcs12="$(_mktemp)"
  _debug2 "temp_pkcs12" "$temp_pkcs12"
  _toPkcs "$temp_pkcs12" "$_ckey" "$_ccert" "$_cca" "$temp_cert_password"
  if [ "$?" != "0" ]; then
    _err "Failed to generate a pkcs12 certificate."
    _err "Please re-run with --debug and report a bug."

    # ensure the temporary certificate file is cleaned up
    [ -f "${temp_pkcs12}" ] && rm -f "${temp_pkcs12}"

    return $?
  fi

  # Load the upload page
  upload_page_html=$(_get "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi?cmd=5914" | tr -d '\n')

  # Get the first instance of XSSID from the upload page
  form_xss_value=$(printf "%s" "$upload_page_html" | _egrep_o 'name="XSSID"\s*value="[^"]+"' | sed 's/^.*="\([^"]\{1,\}\)"$/\1/g' | head -n 1)
  _secure_debug2 "form_xss_value" "$form_xss_value"

  _info "Generating the certificate upload request"
  upload_post_request="$(_mktemp)"
  upload_post_boundary="---------------------------$(date +%Y%m%d%H%M%S)"

  {
    printf -- "--%s\r\n" "${upload_post_boundary}"
    printf "Content-Disposition: form-data; name=\"XSSID\"\r\n\r\n%s\r\n" "${form_xss_value}"
    printf -- "--%s\r\n" "${upload_post_boundary}"
    printf "Content-Disposition: form-data; name=\"http_file\"; filename=\"temp_pkcs12.pfx\"\r\n"
    printf "Content-Type: application/pkcs12\r\n\r\n"
    cat "${temp_pkcs12}"
    printf "\r\n"
    printf -- "--%s\r\n" "${upload_post_boundary}"
    printf "Content-Disposition: form-data; name=\"pwd\"\r\n\r\n%s\r\n" "${temp_cert_password}"
    printf -- "--%s\r\n" "${upload_post_boundary}"
    printf "Content-Disposition: form-data; name=\"cmd\"\r\n\r\n%s\r\n" "31"
    printf -- "--%s\r\n" "${upload_post_boundary}"
    printf "Content-Disposition: form-data; name=\"sysSubmit\"\r\n\r\n%s\r\n" "Import"
    printf -- "--%s--\r\n" "${upload_post_boundary}"
  } >"${upload_post_request}"

  _info "Upload certificate to the switch"

  # Unfortunately we cannot rely upon the switch response across switch models
  # to return a consistent body return - so we cannot inspect the result of this
  # upload to determine success.
  upload_response=$(_zyxel_upload_pkcs12 "${upload_post_request}" "${upload_post_boundary}" 2>&1)
  _debug3 "Upload response: ${upload_response}"
  rm "${upload_post_request}"

  # Pause for a few seconds to give the switch a chance to process the certificate
  # For some reason I've found this to be necessary on my GS1900-24E
  _debug2 "Waiting 4 seconds for the switch to process the newly uploaded certificate."
  sleep "4"

  # Check to see whether or not our update was successful
  _ret=0
  _zyxel_gs1900_should_update
  if [ "$?" != "0" ]; then
    _info "The certificate was updated successfully"
  else
    _ret=1
    _err "The certificate upload does not appear to have worked."
    _err "The remote certificate does not match the certificate we tried to upload."
    _err "Please re-run with --debug 2 and review for unexpected errors. If none can be found please submit a bug."
  fi

  # ensure the temporary files are cleaned up
  [ -f "${temp_pkcs12}" ] && rm -f "${temp_pkcs12}"

  return $_ret
}

# make the certificate upload request using either
# --data binary with @ for file access in CURL
# or using --post-file for wget to ensure we upload
# the pkcs12 without getting tripped up on null bytes
#
# Usage _zyxel_upload_pkcs12 [body file name] [post boundary marker]
_zyxel_upload_pkcs12() {
  bodyfilename="$1"
  multipartformmarker="$2"
  _post_url="${_zyxel_switch_base_uri}/cgi-bin/httpuploadcert.cgi"
  httpmethod="POST"
  _postContentType="multipart/form-data; boundary=${multipartformmarker}"

  if [ -z "$httpmethod" ]; then
    httpmethod="POST"
  fi
  _debug $httpmethod
  _debug "_post_url" "$_post_url"
  _debug2 "bodyfilename" "$bodyfilename"
  _debug2 "_postContentType" "$_postContentType"

  _inithttp

  if [ "$_ACME_CURL" ] && [ "${ACME_USE_WGET:-0}" = "0" ]; then
    _CURL="$_ACME_CURL"
    if [ "$HTTPS_INSECURE" ]; then
      _CURL="$_CURL --insecure  "
    fi
    if [ "$httpmethod" = "HEAD" ]; then
      _CURL="$_CURL -I  "
    fi
    _debug "_CURL" "$_CURL"

    response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" --data-binary "@${bodyfilename}" "$_post_url")"

    _ret="$?"
    if [ "$_ret" != "0" ]; then
      _err "Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: $_ret"
      if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
        _err "Here is the curl dump log:"
        _err "$(cat "$_CURL_DUMP")"
      fi
    fi
  elif [ "$_ACME_WGET" ]; then
    _WGET="$_ACME_WGET"
    if [ "$HTTPS_INSECURE" ]; then
      _WGET="$_WGET --no-check-certificate "
    fi
    _debug "_WGET" "$_WGET"

    response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --post-file="${bodyfilename}" "$_post_url" 2>"$HTTP_HEADER")"

    _ret="$?"
    if [ "$_ret" = "8" ]; then
      _ret=0
      _debug "wget returned 8 as the server returned a 'Bad Request' response. Let's process the response later."
    fi
    if [ "$_ret" != "0" ]; then
      _err "Please refer to https://www.gnu.org/software/wget/manual/html_node/Exit-Status.html for error code: $_ret"
    fi
    if _contains "$_WGET" " -d "; then
      # Demultiplex wget debug output
      cat "$HTTP_HEADER" >&2
      _sed_i '/^[^ ][^ ]/d; /^ *$/d' "$HTTP_HEADER"
    fi
    # remove leading whitespaces from header to match curl format
    _sed_i 's/^  //g' "$HTTP_HEADER"
  else
    _ret="$?"
    _err "Neither curl nor wget have been found, cannot make $httpmethod request."
  fi
  _debug "_ret" "$_ret"
  printf "%s" "$response"
  return $_ret
}

_zyxel_gs1900_trigger_reboot() {
  # Trigger a reboot via the management reboot page in the web ui
  reboot_page_html=$(_get "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi?cmd=5888" | tr -d '\n')
  reboot_xss_value=$(printf "%s" "$reboot_page_html" | _egrep_o 'name="XSSID"\s*value="[^"]+"' | sed 's/^.*="\([^"]\{1,\}\)"$/\1/g')
  _secure_debug2 "reboot_xss_value" "$reboot_xss_value"

  reboot_response_html=$(_post "XSSID=${reboot_xss_value}&cmd=5889&sysSubmit=Reboot" "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi" '' "POST" "application/x-www-form-urlencoded")
  reboot_message=$(printf "%s" "$reboot_response_html" | tr -d '\t\r\n\v\f' | _egrep_o "Rebooting now...")

  if [ -z "$reboot_message" ]; then
    _err "Failed to trigger switch reboot!"
    return 1
  fi

  return 0
}

# password
_zyxel_gs1900_password_obfuscate() {
  # Return the password obfuscated via the same method used by the
  # switch's web UI login process
  echo "$1" | awk '{
    encoded = "";
    password = $1;
    allowed = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    len = length($1);
    pwi = length($1);

    for (i=1; i <= (321 - pwi); i++)
    {
      if (0 == i % 5 && pwi > 0)
      {
        encoded = (encoded)(substr(password, pwi--, 1));
      }
      else if (i == 123)
      {
        if (len < 10)
        {
          encoded = (encoded)(0);
        }
        else
        {
          encoded = (encoded)(int(len / 10));
        }
      }
      else if (i == 289)
      {
        encoded = (encoded)(len % 10)
      }
      else
      {
        encoded = (encoded)(substr(allowed, int(rand() * length(allowed)), 1))
      }
    }
    printf("%s", encoded);
  }'
}

# html label
_zyxel_html_table_lookup() {
  # Look up a value in the html representing the status page of the switch
  # when provided with the html of the page and the label (i.e. "Model Name:")
  html="$1"
  label=$(printf "%s" "$2" | tr -d ' ')
  lookup_result=$(printf "%s" "$html" | tr -d "\t\r\n\v\f" | sed 's/<tr>/\n<tr>/g' | sed 's/<td[^>]*>/<td>/g' | tr -d ' ' | grep -i "$label" | sed "s/<tr><td>$label<\/td><td>\([^<]\{1,\}\)<\/td><\/tr>/\1/i")
  printf "%s" "$lookup_result"
  return 0
}

# html
_zyxel_gs1900_get_model() {
  html="$1"
  model_name=$(_zyxel_html_table_lookup "$html" "Model Name:")
  printf "%s" "$model_name"
}

# html
_zyxel_gs1900_get_firmware_version() {
  html="$1"
  firmware_version=$(_zyxel_html_table_lookup "$html" "Firmware Version:" | _egrep_o "V[^.]+.[^(]+")
  printf "%s" "$firmware_version"
}

# version_number
_zyxel_gs1900_parse_major_version() {
  printf "%s" "$1" | sed 's/^V\([0-9]\{1,\}\).\{1,\}$/\1/gi'
}

# version_number
_zyxel_gs1900_parse_minor_version() {
  printf "%s" "$1" | sed 's/^.\{1,\}\.\([0-9]\{1,\}\)$/\1/gi'
}
