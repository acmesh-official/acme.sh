#!/usr/bin/env bash

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

proxmoxve_deploy(){
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  # "Sane" defaults.
  _target_hostname="$_cdomain"
  if [ -n "$DEPLOY_PROXMOXVE_SERVER" ];then
    _target_hostname="$DEPLOY_PROXMOXVE_SERVER"
  fi

  _target_port="8006"
  if [ -n "$DEPLOY_PROXMOXVE_SERVER_PORT" ];then
    _target_port="$DEPLOY_PROXMOXVE_SERVER_PORT"
  fi

  if [ -n "$DEPLOY_PROXMOXVE_NODE_NAME" ];then
    _node_name="$DEPLOY_PROXMOXVE_NODE_NAME"
  else
    _node_name=$(echo "$_target_hostname"|cut -d. -f1)
  fi

  # Complete URL.
  _target_url="https://${_target_hostname}:${_target_port}/api2/json/nodes/${_node_name}/certificates/custom"

  # More "sane" defaults.
  _proxmoxve_user="root"
  if [ -n "$_proxmoxve_user" ];then
    _proxmoxve_user="$DEPLOY_PROXMOXVE_USER"
  fi

  _proxmoxve_user_realm="pam"
  if [ -n "$DEPLOY_PROXMOXVE_USER_REALM" ];then
    _proxmoxve_user_realm="$DEPLOY_PROXMOXVE_USER_REALM"
  fi

  _proxmoxve_api_token_name="acme"
  if [ -n "$DEPLOY_PROXMOXVE_API_TOKEN_NAME" ];then
    _proxmoxve_api_token_name="$DEPLOY_PROXMOXVE_API_TOKEN_NAME"
  fi

  # This is required.
  _proxmoxve_api_token_key="$DEPLOY_PROXMOXVE_API_TOKEN_KEY"
  if [ -z "$_proxmoxve_api_token_key" ];then
    _err "API key not provided."
    return 1
  fi

  # PVE API Token header value. Used in "Authorization: PVEAPIToken".
  _proxmoxve_header_api_token="${_proxmoxve_user}@${_proxmoxve_user_realm}!${_proxmoxve_api_token_name}=${_proxmoxve_api_token_key}"

  # Generate the data file curl will pass as the data.
  _proxmoxve_temp_data="/tmp/proxmoxve_api/$_cdomain"
  _proxmoxve_temp_data_file="$_proxmoxve_temp_data/body.json"
  # We delete this directory at the end of the script to avoid any conflicts.
  if [ ! -d "$_proxmoxve_temp_data" ];then
    mkdir -p "$_proxmoxve_temp_data"
    # Set to 700 since this file will contain the private key contents.
    chmod 700 "$_proxmoxve_temp_data"
  fi
  # Ugly. I hate putting heredocs inside functions because heredocs don't
  # account for whitespace correctly but it _does_ work and is several times
  # cleaner than anything else I had here.
  #
  # This dumps the json payload to a variable that should be passable to the
  # _psot function.
  _json_payload=$(cat << HEREDOC
{
  "certificates": "$(tr '\n' ':' < "$_cfullchain" | sed 's/:/\\n/g')",
  "key": "$(tr '\n' ':' < "$_ckey" |sed 's/:/\\n/g')",
  "node":"$_node_name",
  "restart":"1",
  "force":"1"
}
HEREDOC
)
  # Push certificates to server.
  export _HTTPS_INSECURE=1
  export ="Authorization: PVEAPIToken=${_proxmoxve_header_api_token}"
  _post "$_json_payload" "$_target_url"

}
