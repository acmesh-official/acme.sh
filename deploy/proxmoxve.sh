#!/usr/bin/env sh

# Deploy certificates to a proxmox virtual environment node using the API.
#
# Environment variables that can be set are:
# `DEPLOY_PROXMOXVE_SERVER`: The hostname of the proxmox ve node. Defaults to
#                            _cdomain.
# `DEPLOY_PROXMOXVE_SERVER_PORT`: The port number the management interface is on.
#                                 Defaults to 8006.
# `DEPLOY_PROXMOXVE_NODE_NAME`: The name of the node we'll be connecting to.
#                               Defaults to the host portion of the server
#                               domain name.
# `DEPLOY_PROXMOXVE_USER`: The user we'll connect as. Defaults to root.
# `DEPLOY_PROXMOXVE_USER_REALM`: The authentication realm the user authenticates
#                                with. Defaults to pam.
# `DEPLOY_PROXMOXVE_API_TOKEN_NAME`: The name of the API token created for the
#                                    user account. Defaults to acme.
# `DEPLOY_PROXMOXVE_API_TOKEN_KEY`: The API token. Required.

proxmoxve_deploy() {
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
  _getdeployconf DEPLOY_PROXMOXVE_SERVER
  if [ -z "$DEPLOY_PROXMOXVE_SERVER" ]; then
    _target_hostname="$_cdomain"
  else
    _target_hostname="$DEPLOY_PROXMOXVE_SERVER"
    _savedeployconf DEPLOY_PROXMOXVE_SERVER "$DEPLOY_PROXMOXVE_SERVER"
  fi
  _debug2 DEPLOY_PROXMOXVE_SERVER "$_target_hostname"

  _getdeployconf DEPLOY_PROXMOXVE_SERVER_PORT
  if [ -z "$DEPLOY_PROXMOXVE_SERVER_PORT" ]; then
    _target_port="8006"
  else
    _target_port="$DEPLOY_PROXMOXVE_SERVER_PORT"
    _savedeployconf DEPLOY_PROXMOXVE_SERVER_PORT "$DEPLOY_PROXMOXVE_SERVER_PORT"
  fi
  _debug2 DEPLOY_PROXMOXVE_SERVER_PORT "$_target_port"

  _getdeployconf DEPLOY_PROXMOXVE_NODE_NAME
  if [ -z "$DEPLOY_PROXMOXVE_NODE_NAME" ]; then
    _node_name=$(echo "$_target_hostname" | cut -d. -f1)
  else
    _node_name="$DEPLOY_PROXMOXVE_NODE_NAME"
    _savedeployconf DEPLOY_PROXMOXVE_NODE_NAME "$DEPLOY_PROXMOXVE_NODE_NAME"
  fi
  _debug2 DEPLOY_PROXMOXVE_NODE_NAME "$_node_name"

  # Complete URL.
  _target_url="https://${_target_hostname}:${_target_port}/api2/json/nodes/${_node_name}/certificates/custom"
  _debug TARGET_URL "$_target_url"

  # More "sane" defaults.
  _getdeployconf DEPLOY_PROXMOXVE_USER
  if [ -z "$DEPLOY_PROXMOXVE_USER" ]; then
    _proxmoxve_user="root"
  else
    _proxmoxve_user="$DEPLOY_PROXMOXVE_USER"
    _savedeployconf DEPLOY_PROXMOXVE_USER "$DEPLOY_PROXMOXVE_USER"
  fi
  _debug2 DEPLOY_PROXMOXVE_USER "$_proxmoxve_user"

  _getdeployconf DEPLOY_PROXMOXVE_USER_REALM
  if [ -z "$DEPLOY_PROXMOXVE_USER_REALM" ]; then
    _proxmoxve_user_realm="pam"
  else
    _proxmoxve_user_realm="$DEPLOY_PROXMOXVE_USER_REALM"
    _savedeployconf DEPLOY_PROXMOXVE_USER_REALM "$DEPLOY_PROXMOXVE_USER_REALM"
  fi
  _debug2 DEPLOY_PROXMOXVE_USER_REALM "$_proxmoxve_user_realm"

  _getdeployconf DEPLOY_PROXMOXVE_API_TOKEN_NAME
  if [ -z "$DEPLOY_PROXMOXVE_API_TOKEN_NAME" ]; then
    _proxmoxve_api_token_name="acme"
  else
    _proxmoxve_api_token_name="$DEPLOY_PROXMOXVE_API_TOKEN_NAME"
    _savedeployconf DEPLOY_PROXMOXVE_API_TOKEN_NAME "$DEPLOY_PROXMOXVE_API_TOKEN_NAME"
  fi
  _debug2 DEPLOY_PROXMOXVE_API_TOKEN_NAME "$_proxmoxve_api_token_name"

  # This is required.
  _getdeployconf DEPLOY_PROXMOXVE_API_TOKEN_KEY
  if [ -z "$DEPLOY_PROXMOXVE_API_TOKEN_KEY" ]; then
    _err "API key not provided."
    return 1
  else
    _proxmoxve_api_token_key="$DEPLOY_PROXMOXVE_API_TOKEN_KEY"
    _savedeployconf DEPLOY_PROXMOXVE_API_TOKEN_KEY "$DEPLOY_PROXMOXVE_API_TOKEN_KEY"
  fi
  _debug2 DEPLOY_PROXMOXVE_API_TOKEN_KEY "$_proxmoxve_api_token_key"

  # PVE API Token header value. Used in "Authorization: PVEAPIToken".
  _proxmoxve_header_api_token="${_proxmoxve_user}@${_proxmoxve_user_realm}!${_proxmoxve_api_token_name}=${_proxmoxve_api_token_key}"
  _debug2 "Auth Header" "$_proxmoxve_header_api_token"

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
  "node":"$_node_name",
  "restart":"1",
  "force":"1"
}
HEREDOC
  )
  _debug2 Payload "$_json_payload"

  _info "Push certificates to server"
  export HTTPS_INSECURE=1
  export _H1="Authorization: PVEAPIToken=${_proxmoxve_header_api_token}"
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
