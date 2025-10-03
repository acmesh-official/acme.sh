#!/usr/bin/env sh

# Deploy certificates to a proxmox backup server using the API.
#
# Environment variables that can be set are:
# `DEPLOY_PROXMOXBS_SERVER`: The hostname of the proxmox backup server. Defaults to
#                            _cdomain.
# `DEPLOY_PROXMOXBS_SERVER_PORT`: The port number the management interface is on.
#                                 Defaults to 8007.
# `DEPLOY_PROXMOXBS_USER`: The user we'll connect as. Defaults to root.
# `DEPLOY_PROXMOXBS_USER_REALM`: The authentication realm the user authenticates
#                                with. Defaults to pam.
# `DEPLOY_PROXMOXBS_API_TOKEN_NAME`: The name of the API token created for the
#                                    user account. Defaults to acme.
# `DEPLOY_PROXMOXBS_API_TOKEN_KEY`: The API token. Required.

proxmoxbs_deploy() {
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
  _getdeployconf DEPLOY_PROXMOXBS_SERVER
  if [ -z "$DEPLOY_PROXMOXBS_SERVER" ]; then
    _target_hostname="$_cdomain"
  else
    _target_hostname="$DEPLOY_PROXMOXBS_SERVER"
    _savedeployconf DEPLOY_PROXMOXBS_SERVER "$DEPLOY_PROXMOXBS_SERVER"
  fi
  _debug2 DEPLOY_PROXMOXBS_SERVER "$_target_hostname"

  _getdeployconf DEPLOY_PROXMOXBS_SERVER_PORT
  if [ -z "$DEPLOY_PROXMOXBS_SERVER_PORT" ]; then
    _target_port="8007"
  else
    _target_port="$DEPLOY_PROXMOXBS_SERVER_PORT"
    _savedeployconf DEPLOY_PROXMOXBS_SERVER_PORT "$DEPLOY_PROXMOXBS_SERVER_PORT"
  fi
  _debug2 DEPLOY_PROXMOXBS_SERVER_PORT "$_target_port"

  # Complete URL.
  _target_url="https://${_target_hostname}:${_target_port}/api2/json/nodes/localhost/certificates/custom"
  _debug TARGET_URL "$_target_url"

  # More "sane" defaults.
  _getdeployconf DEPLOY_PROXMOXBS_USER
  if [ -z "$DEPLOY_PROXMOXBS_USER" ]; then
    _proxmoxbs_user="root"
  else
    _proxmoxbs_user="$DEPLOY_PROXMOXBS_USER"
    _savedeployconf DEPLOY_PROXMOXBS_USER "$DEPLOY_PROXMOXBS_USER"
  fi
  _debug2 DEPLOY_PROXMOXBS_USER "$_proxmoxbs_user"

  _getdeployconf DEPLOY_PROXMOXBS_USER_REALM
  if [ -z "$DEPLOY_PROXMOXBS_USER_REALM" ]; then
    _proxmoxbs_user_realm="pam"
  else
    _proxmoxbs_user_realm="$DEPLOY_PROXMOXBS_USER_REALM"
    _savedeployconf DEPLOY_PROXMOXBS_USER_REALM "$DEPLOY_PROXMOXBS_USER_REALM"
  fi
  _debug2 DEPLOY_PROXMOXBS_USER_REALM "$_proxmoxbs_user_realm"

  _getdeployconf DEPLOY_PROXMOXBS_API_TOKEN_NAME
  if [ -z "$DEPLOY_PROXMOXBS_API_TOKEN_NAME" ]; then
    _proxmoxbs_api_token_name="acme"
  else
    _proxmoxbs_api_token_name="$DEPLOY_PROXMOXBS_API_TOKEN_NAME"
    _savedeployconf DEPLOY_PROXMOXBS_API_TOKEN_NAME "$DEPLOY_PROXMOXBS_API_TOKEN_NAME"
  fi
  _debug2 DEPLOY_PROXMOXBS_API_TOKEN_NAME "$_proxmoxbs_api_token_name"

  # This is required.
  _getdeployconf DEPLOY_PROXMOXBS_API_TOKEN_KEY
  if [ -z "$DEPLOY_PROXMOXBS_API_TOKEN_KEY" ]; then
    _err "API key not provided."
    return 1
  else
    _proxmoxbs_api_token_key="$DEPLOY_PROXMOXBS_API_TOKEN_KEY"
    _savedeployconf DEPLOY_PROXMOXBS_API_TOKEN_KEY "$DEPLOY_PROXMOXBS_API_TOKEN_KEY"
  fi
  _debug2 DEPLOY_PROXMOXBS_API_TOKEN_KEY "$_proxmoxbs_api_token_key"

  # PBS API Token header value. Used in "Authorization: PBSAPIToken".
  _proxmoxbs_header_api_token="${_proxmoxbs_user}@${_proxmoxbs_user_realm}!${_proxmoxbs_api_token_name}:${_proxmoxbs_api_token_key}"
  _debug2 "Auth Header" "$_proxmoxbs_header_api_token"

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
  "node":"localhost",
  "restart":true,
  "force":true
}
HEREDOC
  )
  _debug2 Payload "$_json_payload"

  _info "Push certificates to server"
  export HTTPS_INSECURE=1
  export _H1="Authorization: PBSAPIToken=${_proxmoxbs_header_api_token}"
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
