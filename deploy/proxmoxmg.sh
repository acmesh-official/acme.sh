#!/usr/bin/bash

# Deploy certificates to a proxmox mail gateway using the API.
#
# Environment variables that can be set are:
# `DEPLOY_PROXMOXMG_SERVER`: The hostname of the proxmox backup server. Defaults to
#                            _cdomain.
# `DEPLOY_PROXMOXMG_SERVER_PORT`: The port number the management interface is on.
#                                 Defaults to 8006.
# `DEPLOY_PROXMOXMG_USER`: The user we'll connect as. Defaults to root.
# `DEPLOY_PROXMOXMG_USER_REALM`: The authentication realm the user authenticates
#                                with. Defaults to pam.
# `DEPLOY_PROXMOXMG_PASSWORD`: The password for the user account. Required.
# `DEPLOY_PROXMOXMG_CERTIFICATE_TYPE`: Certificate type to deploy. Either 'api' or
#                                    'smtp'. Defaults to 'api'.


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
    _target_hostname="$_cdomain"
  else
    _target_hostname="$DEPLOY_PROXMOXMG_SERVER"
    _savedeployconf DEPLOY_PROXMOXMG_SERVER "$DEPLOY_PROXMOXMG_SERVER"
  fi
  _debug2 DEPLOY_PROXMOXMG_SERVER "$_target_hostname"

  _getdeployconf DEPLOY_PROXMOXMG_SERVER_PORT
  if [ -z "$DEPLOY_PROXMOXMG_SERVER_PORT" ]; then
    _target_port="8006"
  else
    _target_port="$DEPLOY_PROXMOXMG_SERVER_PORT"
    _savedeployconf DEPLOY_PROXMOXMG_SERVER_PORT "$DEPLOY_PROXMOXMG_SERVER_PORT"
  fi
  _debug2 DEPLOY_PROXMOXMG_SERVER_PORT "$_target_port"

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
  _debug2 DEPLOY_PROXMOXMG_PASSWORD "$_proxmoxmg_password"

  _getdeployconf DEPLOY_PROXMOXMG_CERTIFICATE_TYPE
  if [ -z "$DEPLOY_PROXMOXMG_CERTIFICATE_TYPE" ]; then
    _target_certificate_type="api"
  else
    _target_certificate_type="$DEPLOY_PROXMOXMG_CERTIFICATE_TYPE"
    _savedeployconf DEPLOY_PROXMOXMG_CERTIFICATE_TYPE "$DEPLOY_PROXMOXMG_CERTIFICATE_TYPE"
  fi
  _debug2 DEPLOY_PROXMOXMG_CERTIFICATE_TYPE "$_target_certificate_type"

  # Complete URL.
  _target_url="https://${_target_hostname}:${_target_port}/api2/json/nodes/localhost/certificates/custom/${_target_certificate_type}"
  _debug TARGET_URL "$_target_url"

  # PMG API Ticket retrieval.
  _debug2 "Retrieve API Ticket"
  response=$(_post "{\"username\":\"${_proxmoxmg_user}@${_proxmoxmg_user_realm}\",\"password\":\"${_proxmoxmg_password}\"}" "https://${_target_hostname}:${_target_port}/api2/json/access/ticket" "" POST "application/json")
  _retval=$?
  if [ "${_retval}" -ne 0 ]; then
    _err "Proxmox Backup Server API authentication failed."
    _debug "Response" "$response"
    return 1
  fi

  # Extract ticket and CSRFPreventionToken from response.
  _proxmoxmg_ticket=$(echo "$response" | _egrep_o '"ticket"\s*:\s*"[^\"]+"' | cut -d'"' -f4)
  _proxmoxmg_csrf_token=$(echo "$response" | _egrep_o '"CSRFPreventionToken"\s*:\s*"[^\"]+"' | cut -d'"' -f4)

  _debug2 "_proxmoxmg_ticket" "$_proxmoxmg_ticket"
  _debug2 "_proxmoxmg_csrf_token" "$_proxmoxmg_csrf_token"

  _proxmoxmg_header_api_token="Cookie: PMGAuthCookie=${_proxmoxmg_ticket}"
  _debug2 "Auth Header" "$_proxmoxmg_header_api_token"
  # Ugly. I hate putting heredocs inside functions because heredocs don't
  # account for whitespace correctly but it _does_ work and is several times
  # cleaner than anything else I had here.
  #
  # This dumps the json payload to a variable that should be passable to the
  # _psot function.
  _json_payload=$(
    cat <<HEREDOC
{
  "certificates": "$(tr '\n' ':' <"$_cfullchain" | sed 's/:/\\n/g')",
  "key": "$(tr '\n' ':' <"$_ckey" | sed 's/:/\\n/g')",
  "restart":true,
  "force":true
}
HEREDOC
  )
  _debug2 Payload "$_json_payload"

  _info "Push certificates to server"
  export _H1="${_proxmoxmg_header_api_token}"
  export _H2="CSRFPreventionToken: ${_proxmoxmg_csrf_token}"
  response=$(_post "$_json_payload" "$_target_url" "" POST "application/json")
  _retval=$?
  if [ "${_retval}" -eq 0 ]; then
    _debug3 response "$response"
    _info "Certificate successfully deployed"
    return 0
  else
    _err "Certificate deployment failed"
    _debug "Response" "$response"
    return 1
  fi

}
