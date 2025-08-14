#!/usr/bin/env sh

# Here is a script to deploy cert to Ruckus ZoneDirector / Unleashed.
#
# Public domain, 2024, Tony Rielly <https://github.com/ms264556>
#
# ```sh
# acme.sh --deploy -d ruckus.example.com --deploy-hook ruckus
# ```
#
# Then you need to set the environment variables for the
# deploy script to work.
#
# ```sh
# export RUCKUS_HOST=myruckus.example.com
# export RUCKUS_USER=myruckususername
# export RUCKUS_PASS=myruckuspassword
#
# acme.sh --deploy -d myruckus.example.com --deploy-hook ruckus
# ```
#
# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
ruckus_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _err_code=0

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  _getdeployconf RUCKUS_HOST
  _getdeployconf RUCKUS_USER
  _getdeployconf RUCKUS_PASS

  if [ -z "$RUCKUS_HOST" ]; then
    _debug "Using _cdomain as RUCKUS_HOST, please set if not correct."
    RUCKUS_HOST="$_cdomain"
  fi

  if [ -z "$RUCKUS_USER" ]; then
    _err "Need to set the env variable RUCKUS_USER"
    return 1
  fi

  if [ -z "$RUCKUS_PASS" ]; then
    _err "Need to set the env variable RUCKUS_PASS"
    return 1
  fi

  _savedeployconf RUCKUS_HOST "$RUCKUS_HOST"
  _savedeployconf RUCKUS_USER "$RUCKUS_USER"
  _savedeployconf RUCKUS_PASS "$RUCKUS_PASS"

  _debug RUCKUS_HOST "$RUCKUS_HOST"
  _debug RUCKUS_USER "$RUCKUS_USER"
  _secure_debug RUCKUS_PASS "$RUCKUS_PASS"

  export ACME_HTTP_NO_REDIRECTS=1

  _info "Discovering the login URL"
  _get "https://$RUCKUS_HOST" >/dev/null
  _login_url="$(_response_header 'Location')"
  if [ -n "$_login_url" ]; then
    _login_path=$(echo "$_login_url" | sed 's|https\?://[^/]\+||')
    if [ -z "$_login_path" ]; then
      # redirect was to a different host
      _err "Connection failed: redirected to a different host. Configure Unleashed with a Preferred Master or Management Interface."
      return 1
    fi
  fi

  if [ -z "${_login_url}" ]; then
    _err "Connection failed: couldn't find login page."
    return 1
  fi

  _base_url=$(dirname "$_login_url")
  _login_page=$(basename "$_login_url")

  if [ "$_login_page" = "index.html" ]; then
    _err "Connection temporarily unavailable: Unleashed Rebuilding."
    return 1
  fi

  if [ "$_login_page" = "wizard.jsp" ]; then
    _err "Connection failed: Setup Wizard not complete."
    return 1
  fi

  _info "Login"
  _username_encoded="$(printf "%s" "$RUCKUS_USER" | _url_encode)"
  _password_encoded="$(printf "%s" "$RUCKUS_PASS" | _url_encode)"
  _login_query="$(printf "%s" "username=${_username_encoded}&password=${_password_encoded}&ok=Log+In")"
  _post "$_login_query" "$_login_url" >/dev/null

  _login_code="$(_response_code)"
  if [ "$_login_code" = "200" ]; then
    _err "Login failed: incorrect credentials."
    return 1
  fi

  _info "Collect Session Cookie"
  _H1="Cookie: $(_response_cookie)"
  export _H1
  _info "Collect CSRF Token"
  _H2="X-CSRF-Token: $(_response_header 'HTTP_X_CSRF_TOKEN')"
  export _H2

  if _isRSA "$_ckey" >/dev/null 2>&1; then
    _debug "Using RSA certificate."
  else
    _info "Verifying ECC certificate support."

    _ul_version="$(_get_unleashed_version)"
    if [ -z "$_ul_version" ]; then
      _err "Your controller doesn't support ECC certificates. Please deploy an RSA certificate."
      return 1
    fi

    _ul_version_major="$(echo "$_ul_version" | cut -d . -f 1)"
    _ul_version_minor="$(echo "$_ul_version" | cut -d . -f 2)"
    if [ "$_ul_version_major" -lt "200" ]; then
      _err "ZoneDirector doesn't support ECC certificates. Please deploy an RSA certificate."
      return 1
    elif [ "$_ul_version_minor" -lt "13" ]; then
      _err "Unleashed $_ul_version_major.$_ul_version_minor doesn't support ECC certificates. Please deploy an RSA certificate or upgrade to Unleashed 200.13+."
      return 1
    fi

    _debug "ECC certificates OK for Unleashed $_ul_version_major.$_ul_version_minor."
  fi

  _info "Uploading certificate"
  _post_upload "uploadcert" "$_cfullchain"

  _info "Uploading private key"
  _post_upload "uploadprivatekey" "$_ckey"

  _info "Replacing certificate"
  _replace_cert_ajax='<ajax-request action="docmd" comp="system" updater="rid.0.5" xcmd="replace-cert" checkAbility="6" timeout="-1"><xcmd cmd="replace-cert" cn="'$RUCKUS_HOST'"/></ajax-request>'
  _post "$_replace_cert_ajax" "$_base_url/_cmdstat.jsp" >/dev/null

  _info "Rebooting"
  _cert_reboot_ajax='<ajax-request action="docmd" comp="worker" updater="rid.0.5" xcmd="cert-reboot" checkAbility="6"><xcmd cmd="cert-reboot" action="undefined"/></ajax-request>'
  _post "$_cert_reboot_ajax" "$_base_url/_cmdstat.jsp" >/dev/null

  return 0
}

_response_code() {
  _egrep_o <"$HTTP_HEADER" "^HTTP[^ ]* .*$" | cut -d " " -f 2-100 | tr -d "\f\n" | _egrep_o "^[0-9]*"
}

_response_header() {
  grep <"$HTTP_HEADER" -i "^$1:" | cut -d ':' -f 2- | tr -d "\r\n\t "
}

_response_cookie() {
  _response_header 'Set-Cookie' | sed 's/;.*//'
}

_get_unleashed_version() {
  _post '<ajax-request action="getstat" comp="system"><sysinfo/></ajax-request>' "$_base_url/_cmdstat.jsp" | _egrep_o "version-num=\"[^\"]*\"" | cut -d '"' -f 2
}

_post_upload() {
  _post_action="$1"
  _post_file="$2"

  _post_boundary="----FormBoundary$(date "+%s%N")"

  _post_data="$({
    printf -- "--%s\r\n" "$_post_boundary"
    printf -- "Content-Disposition: form-data; name=\"u\"; filename=\"%s\"\r\n" "$_post_action"
    printf -- "Content-Type: application/octet-stream\r\n\r\n"
    printf -- "%s\r\n" "$(cat "$_post_file")"

    printf -- "--%s\r\n" "$_post_boundary"
    printf -- "Content-Disposition: form-data; name=\"action\"\r\n\r\n"
    printf -- "%s\r\n" "$_post_action"

    printf -- "--%s\r\n" "$_post_boundary"
    printf -- "Content-Disposition: form-data; name=\"callback\"\r\n\r\n"
    printf -- "%s\r\n" "uploader_$_post_action"

    printf -- "--%s--\r\n\r\n" "$_post_boundary"
  })"

  _post "$_post_data" "$_base_url/_upload.jsp?request_type=xhr" "" "" "multipart/form-data; boundary=$_post_boundary" >/dev/null
}
