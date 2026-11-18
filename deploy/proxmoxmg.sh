#!/usr/bin/env sh

# Deploy certificates to a proxmox mail gateway using the API.
#
# Environment variables that can be set are:
# `DEPLOY_PROXMOXMG_SERVER`: The hostname of the proxmox mail gateway. Defaults to
#                            _cdomain.
# `DEPLOY_PROXMOXMG_SERVER_PORT`: The port number the management interface is on.
#                                 Defaults to 8006.
# `DEPLOY_PROXMOXMG_USER`: The user we'll connect as. Defaults to root.
# `DEPLOY_PROXMOXMG_USER_REALM`: The authentication realm the user authenticates
#                                with. Defaults to pam.
# `DEPLOY_PROXMOXMG_PASSWORD`: The password for the user account.
# `DEPLOY_PROXMOXMG_CERTIFICATE_TYPE`: Certificate type(s) to deploy. Either 'api',
#                                    'smtp' or 'api smtp'. Defaults to 'api smtp'.

proxmoxmg_deploy() {
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

  # "Sane" defaults.
  _getdeployconf DEPLOY_PROXMOXMG_SERVER
  if [ -z "$DEPLOY_PROXMOXMG_SERVER" ]; then
    _proxmoxmg_hostname="$_cdomain"
  else
    _proxmoxmg_hostname="$DEPLOY_PROXMOXMG_SERVER"
    _savedeployconf DEPLOY_PROXMOXMG_SERVER "$DEPLOY_PROXMOXMG_SERVER"
  fi
  _debug2 DEPLOY_PROXMOXMG_SERVER "$_proxmoxmg_hostname"

  _getdeployconf DEPLOY_PROXMOXMG_SERVER_PORT
  if [ -z "$DEPLOY_PROXMOXMG_SERVER_PORT" ]; then
    _proxmoxmg_port="8006"
  else
    _proxmoxmg_port="$DEPLOY_PROXMOXMG_SERVER_PORT"
    _savedeployconf DEPLOY_PROXMOXMG_SERVER_PORT "$DEPLOY_PROXMOXMG_SERVER_PORT"
  fi
  _debug2 DEPLOY_PROXMOXMG_SERVER_PORT "$_proxmoxmg_port"

  # Complete URLs.
  _proxmoxmg_base_url="https://${_proxmoxmg_hostname}:${_proxmoxmg_port}/api2/json"
  _proxmoxmg_target_url="${_proxmoxmg_base_url}/nodes/localhost/certificates/custom"
  _debug TARGET_URL "$_proxmoxmg_target_url"

  # More "sane" defaults.
  _getdeployconf DEPLOY_PROXMOXMG_USER
  if [ -z "$DEPLOY_PROXMOXMG_USER" ]; then
    _proxmoxmg_user="root"
  else
    _proxmoxmg_user="$DEPLOY_PROXMOXMG_USER"
    _savedeployconf DEPLOY_PROXMOXMG_USER "$DEPLOY_PROXMOXMG_USER"
  fi
  _debug2 DEPLOY_PROXMOXMG_USER "$_proxmoxmg_user"

  _getdeployconf DEPLOY_PROXMOXMG_USER_REALM
  if [ -z "$DEPLOY_PROXMOXMG_USER_REALM" ]; then
    _proxmoxmg_user_realm="pam"
  else
    _proxmoxmg_user_realm="$DEPLOY_PROXMOXMG_USER_REALM"
    _savedeployconf DEPLOY_PROXMOXMG_USER_REALM "$DEPLOY_PROXMOXMG_USER_REALM"
  fi
  _debug2 DEPLOY_PROXMOXMG_USER_REALM "$_proxmoxmg_user_realm"

  # This is required.
  _getdeployconf DEPLOY_PROXMOXMG_PASSWORD
  if [ -z "$DEPLOY_PROXMOXMG_PASSWORD" ]; then
    _err "User password not provided."
    return 1
  else
    _proxmoxmg_password="$DEPLOY_PROXMOXMG_PASSWORD"
    _savedeployconf DEPLOY_PROXMOXMG_PASSWORD "$DEPLOY_PROXMOXMG_PASSWORD"
  fi
  _secure_debug2 DEPLOY_PROXMOXMG_PASSWORD "$_proxmoxmg_password"

  _getdeployconf DEPLOY_PROXMOXMG_CERTIFICATE_TYPE
  if [ -z "$DEPLOY_PROXMOXMG_CERTIFICATE_TYPE" ]; then
    _proxmoxmg_certificate_types="api smtp"
  else
    _proxmoxmg_certificate_types="$DEPLOY_PROXMOXMG_CERTIFICATE_TYPE"
    _savedeployconf DEPLOY_PROXMOXMG_CERTIFICATE_TYPE "$DEPLOY_PROXMOXMG_CERTIFICATE_TYPE"
  fi
  _debug2 DEPLOY_PROXMOXMG_CERTIFICATE_TYPE "$_proxmoxmg_certificate_types"

  # PMG API ticket retrieval.
  # The body is form-encoded so that any character in the password is safe.
  _debug2 "Retrieve API Ticket"
  export HTTPS_INSECURE=1
  _proxmoxmg_id="${_proxmoxmg_user}@${_proxmoxmg_user_realm}"
  _proxmoxmg_body="username=$(printf '%s' "$_proxmoxmg_id" | _url_encode)"
  _proxmoxmg_body="$_proxmoxmg_body&password=$(printf '%s' "$_proxmoxmg_password" | _url_encode)"
  _proxmoxmg_response=$(_post "$_proxmoxmg_body" "${_proxmoxmg_base_url}/access/ticket")
  _proxmoxmg_retval=$?
  if [ "$_proxmoxmg_retval" -ne 0 ]; then
    _err "Proxmox Mail Gateway API request failed."
    return 1
  fi

  # Extract ticket and CSRFPreventionToken from response.
  # _post returns 0 even on HTTP 401, so an empty ticket means a failed login.
  _proxmoxmg_response="$(echo "$_proxmoxmg_response" | _normalizeJson)"
  _proxmoxmg_ticket=$(echo "$_proxmoxmg_response" | _egrep_o '"ticket":"[^"]*"' | cut -d '"' -f 4)
  _proxmoxmg_csrf_token=$(echo "$_proxmoxmg_response" | _egrep_o '"CSRFPreventionToken":"[^"]*"' | cut -d '"' -f 4)
  _secure_debug2 "_proxmoxmg_ticket" "$_proxmoxmg_ticket"
  _secure_debug2 "_proxmoxmg_csrf_token" "$_proxmoxmg_csrf_token"

  if [ -z "$_proxmoxmg_ticket" ] || [ -z "$_proxmoxmg_csrf_token" ]; then
    _err "Proxmox Mail Gateway API authentication failed."
    return 1
  fi

  _proxmoxmg_header_api_token="Cookie: PMGAuthCookie=${_proxmoxmg_ticket}"
  _secure_debug2 "Auth Header" "$_proxmoxmg_header_api_token"

  # Ugly. I hate putting heredocs inside functions because heredocs don't
  # account for whitespace correctly but it _does_ work and is several times
  # cleaner than anything else I had here.
  #
  # This dumps the json payload to a variable that should be passable to the
  # _post function.
  _proxmoxmg_json_payload=$(
    cat <<HEREDOC
{
  "certificates": "$(tr '\n' ':' <"$_cfullchain" | sed 's/:/\\n/g')",
  "key": "$(tr '\n' ':' <"$_ckey" | sed 's/:/\\n/g')",
  "restart":true,
  "force":true
}
HEREDOC
  )
  _secure_debug2 Payload "$_proxmoxmg_json_payload"

  _info "Push certificates to server"
  export HTTPS_INSECURE=1
  export _H1="${_proxmoxmg_header_api_token}"
  export _H2="CSRFPreventionToken: ${_proxmoxmg_csrf_token}"

  _proxmoxmg_rc=0
  for _proxmoxmg_type in $_proxmoxmg_certificate_types; do
    if ! _proxmoxmg_upload "$_proxmoxmg_type"; then
      # In case of an error, remember it, but keep going for the remaining types.
      _proxmoxmg_rc=1
    fi
  done

  return $_proxmoxmg_rc
}

# Usage: _proxmoxmg_upload <api|smtp>
_proxmoxmg_upload() {
  _proxmoxmg_response=$(_post "$_proxmoxmg_json_payload" "$_proxmoxmg_target_url/$1" "" POST "application/json")
  _proxmoxmg_retval=$?
  # The API errors out with a non-2xx HTTP status and an empty body,
  # so the status line is checked too, not only the response body.
  _proxmoxmg_status="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
  _debug2 "HTTP status" "$_proxmoxmg_status"
  _proxmoxmg_response="$(echo "$_proxmoxmg_response" | _json_decode | _normalizeJson)"
  _proxmoxmg_message=$(echo "$_proxmoxmg_response" | _egrep_o '"message":"[^"]*"' | cut -d '"' -f 4)
  case "$_proxmoxmg_status" in
  2[0-9][0-9])
    if [ "$_proxmoxmg_retval" -eq 0 ] && [ -z "$_proxmoxmg_message" ]; then
      _debug3 response "$_proxmoxmg_response"
      _info "Certificate $1 successfully deployed"
      return 0
    fi
    ;;
  esac
  _err "Certificate $1 deployment failed (HTTP status $_proxmoxmg_status). $_proxmoxmg_message"
  _debug "Response" "$_proxmoxmg_response"
  return 1
}
