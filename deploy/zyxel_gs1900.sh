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
  if [ -z "$DEPLOY_ZYXEL_SWITCH" ]; then
    _zyxel_switch_host="$_cdomain"
  else
    _zyxel_switch_host="$DEPLOY_ZYXEL_SWITCH"
    _savedeployconf DEPLOY_ZYXEL_SWITCH "$DEPLOY_ZYXEL_SWITCH"
  fi
  _debug2 DEPLOY_ZYXEL_SWITCH "$_zyxel_switch_host"

  _getdeployconf DEPLOY_ZYXEL_SWITCH_USER
  if [ -z "$DEPLOY_ZYXEL_SWITCH_USER" ]; then
    _zyxel_switch_user="admin"
  else
    _zyxel_switch_user="$DEPLOY_ZYXEL_SWITCH_USER"
    _savedeployconf DEPLOY_ZYXEL_SWITCH_USER "$DEPLOY_ZYXEL_SWITCH_USER"
  fi
  _debug2 DEPLOY_ZYXEL_SWITCH_USER "$_zyxel_switch_user"

  _getdeployconf DEPLOY_ZYXEL_SWITCH_PASSWORD
  if [ -z "$DEPLOY_ZYXEL_SWITCH_PASSWORD" ]; then
    _zyxel_switch_password="1234"
  else
    _zyxel_switch_password="$DEPLOY_ZYXEL_SWITCH_PASSWORD"
    _savedeployconf DEPLOY_ZYXEL_SWITCH_PASSWORD "$DEPLOY_ZYXEL_SWITCH_PASSWORD"
  fi
  _secure_debug2 DEPLOY_ZYXEL_SWITCH_PASSWORD "$_zyxel_switch_password"

  _getdeployconf DEPLOY_ZYXEL_SWITCH_REBOOT
  if [ -z "$DEPLOY_ZYXEL_SWITCH_REBOOT" ]; then
    _zyxel_switch_reboot="0"
  else
    _zyxel_switch_reboot="$DEPLOY_ZYXEL_SWITCH_REBOOT"
    _savedeployconf DEPLOY_ZYXEL_SWITCH_REBOOT "$DEPLOY_ZYXEL_SWITCH_REBOOT"
  fi
  _debug2 DEPLOY_ZYXEL_SWITCH_REBOOT "$_zyxel_switch_reboot"

  _zyxel_switch_base_uri="https://${_zyxel_switch_host}"

  _info "Beginning to deploy to a Zyxel GS1900 series switch at ${_zyxel_switch_base_uri}."
  _zyxel_gs1900_deployment_precheck || return $?

  _info "Logging into the switch web interface."
  _zyxel_gs1900_login || return $?

  _info "Validating the switch is compatible with this deployment process."
  _zyxel_gs1900_validate_device_compatibility || return $?

  _info "Uploading the certificate."
  _zyxel_gs1900_upload_certificate || return $?

  if [ "$_zyxel_switch_reboot" = "1" ]; then
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
  _post "username=test&password=test&login=true;" "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi" '' "POST" "application/x-www-form-urlencoded" >/dev/null 2>&1
  test_login_page_exitcode="$?"
  if [ "$test_login_page_exitcode" -ne "0" ]; then
    if [ "${ACME_USE_WGET:-0}" = "0" ] && [ "$test_login_page_exitcode" = "56" ]; then
      _info "Warning: curl is returning exit code 56. Please re-run with --debug for more information."
      _debug "If the above curl trace contains the error 'SSL routines::unexpected eof while reading, errno 0'"
      _debug "please ensure you are running the latest versions of curl and openssl. For more information"
      _debug "see: https://github.com/openssl/openssl/issues/18866#issuecomment-1194219601"
    elif { [ "${ACME_USE_WGET:-0}" = "0" ] && [ "$test_login_page_exitcode" = "60" ]; } || { [ "${ACME_USE_WGET:-0}" = "1" ] && [ "$test_login_page_exitcode" = "5" ]; }; then
      _err "The SSL certificate at $_zyxel_switch_base_uri could not be validated."
      _err "Please double check your hostname, port, and that you are actually connecting to your switch."
      _err "If the problem persists then please ensure that the certificate is not self-signed, has not"
      _err "expired, and matches the switch hostname. If you expect validation to fail then you can disable"
      _err "certificate validation by running with --insecure."
      return 1
    else
      _err "Failed to submit the initial login attempt to $_zyxel_switch_base_uri."
      return 1
    fi
  fi
}

_zyxel_gs1900_login() {
  # Login to the switch and set the appropriate auth cookie in _H1
  username_encoded=$(printf "%s" "$_zyxel_switch_user" | _url_encode)
  password_encoded=$(_zyxel_gs1900_password_obfuscate "$_zyxel_switch_password" | _url_encode)

  login_response=$(_post "username=${username_encoded}&password=${password_encoded}&login=true;" "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi" '' "POST" "application/x-www-form-urlencoded" | tr -d '\n')
  auth_response=$(_post "authId=${login_response}&login_chk=true" "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi" '' "POST" "application/x-www-form-urlencoded" | tr -d '\n')
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

  upload_page_html=$(_get "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi?cmd=5914" | tr -d '\n')

  # Get the two validity dates by looking for their date format in the page (i.e. Mar 5 05:48:48 2024 GMT)
  existing_validity=$(_zyxel_html_extract_dates "$upload_page_html")
  _debug2 "existing_validity" "$existing_validity"

  form_xss_value=$(printf "%s" "$upload_page_html" | _egrep_o 'name="XSSID"\s*value="[^"]+"' | sed 's/^.*="\([^"]\{1,\}\)"$/\1/g')
  _secure_debug2 "form_xss_value" "$form_xss_value"

  # If a certificate exists on the switch already there will be two XSS keys - we want the first one
  form_xss_value=$(printf "%s" "$form_xss_value" | head -n 1)
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
  # upload to determine success. We will need to re-query the certificates page
  # and compare the validity dates to try and identify if they have changed.
  _post "${upload_post_request}" "${_zyxel_switch_base_uri}/cgi-bin/httpuploadcert.cgi" '' "POST" "multipart/form-data; boundary=${upload_post_boundary}" '1' >/dev/null 2>&1
  rm "${upload_post_request}"

  # Pause for a few seconds to give the switch a chance to process the certificate
  # For some reason I've found this to be necessary on my GS1900-24E
  _debug2 "Waiting 4 seconds for the switch to process the newly uploaded certificate."
  sleep "4"

  _debug2 "Checking to see if the certificate updated properly"
  upload_page_html=$(_get "${_zyxel_switch_base_uri}/cgi-bin/dispatcher.cgi?cmd=5914" | tr -d '\n')
  new_validity=$(_zyxel_html_extract_dates "$upload_page_html")
  _debug2 "new_validity" "$existing_validity"

  _ret=0
  if [ "$existing_validity" != "$new_validity" ]; then
    _debug2 "The certificate validity has changed. The upload must have succeeded."
  else
    _ret=1
    _err "The certificate upload does not appear to have worked."
    _err "Either the certificate provided has not changed, or the switch is returning an unexpected error."
    _err "Please re-run with --debug 2 and review for unexpected errors. If none can be found please submit a bug."
  fi

  # ensure the temporary files are cleaned up
  [ -f "${temp_pkcs12}" ] && rm -f "${temp_pkcs12}"

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

# html
_zyxel_html_extract_dates() {
  html="$1"
  # Extract all dates in the html which match the format "Mar  5 05:48:48 2024 GMT"
  # Note that the number of spaces between the format sections may differ for some reason
  printf "%s" "$html" | _egrep_o '[A-Za-z]{3}\s+[0-9]+\s+[0-9]+:[0-9]+:[0-9]+\s+[0-9]+\s+[A-Za-z]+'
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

# password
_zyxel_gs1900_password_obfuscate() {
  # Return the password obfuscated via the same method used by the
  # Zyxel Web UI login process
  login_allowed_chrs="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  login_pw_arg="$1"
  login_pw_len="${#login_pw_arg}"
  login_pw_index="${#login_pw_arg}"

  login_pw_obfuscated=""

  i=1
  while [ "$i" -le "$(_math "321" - "$login_pw_index")" ]; do
    append_chr="0"

    if [ "$((i % 5))" -eq 0 ] && [ "$login_pw_index" -gt 0 ]; then
      login_pw_index=$(_math "$login_pw_index" - 1)
      append_chr=$(echo "$login_pw_arg" | awk -v var="$login_pw_index" '{ str=substr($0,var+1,1); print str }')
    elif [ "$i" -eq 123 ]; then
      if [ "${login_pw_len}" -lt 10 ]; then
        # The 123rd character must be 0 if the login_pw_arg is less than 10 characters
        append_chr="0"
      else
        # Or the login_pw_arg divided by 10 rounded down if greater than or equal to 10
        append_chr=$(_math "$login_pw_len" / 10)
      fi
    elif [ $i -eq 289 ]; then
      # the 289th character must be the len % 10
      append_chr=$(_math "$login_pw_len" % 10)
    else
      # add random characters for the sake of obfuscation...
      rand=$(head -q /dev/urandom | tr -cd '0-9' | head -c5 | sed 's/^0\{1,\}//')
      rand=$(printf "%5d" "$rand")
      rand_idx=$(_math "$rand" % "${#login_allowed_chrs}")
      append_chr=$(echo "$login_allowed_chrs" | awk -v var="$rand_idx" '{ str=substr($0,var+1,1); print str }')
    fi

    login_pw_obfuscated="${login_pw_obfuscated}${append_chr}"
    i=$(_math "$i" + 1)
  done

  printf "%s" "$login_pw_obfuscated"
}

_zyxel_gs1900_get_model() {
  html="$1"
  model_name=$(_zyxel_html_table_lookup "$html" "Model Name:")
  printf "%s" "$model_name"
}

_zyxel_gs1900_get_firmware_version() {
  html="$1"
  firmware_version=$(_zyxel_html_table_lookup "$html" "Firmware Version:" | _egrep_o "V[^.]+.[^(]+")
  printf "%s" "$firmware_version"
}

_zyxel_gs1900_parse_major_version() {
  printf "%s" "$1" | sed 's/^V\([0-9]\{1,\}\).\{1,\}$/\1/gi'
}

_zyxel_gs1900_parse_minor_version() {
  printf "%s" "$1" | sed 's/^.\{1,\}\.\([0-9]\{1,\}\)$/\1/gi'
}
