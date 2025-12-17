#!/usr/bin/env sh

# Script to deploy certificates to remote cPanel server by SSH
# This is a rough mashup of deploy/ssh.sh and deploy/cpanel_uapi.sh
# Note that SSH must be able to login to remote host without a password...
# SSH Keys must have been exchanged with the remote host.  Validate and
# test that you can login to USER@SERVER from the host running acme.sh before
# using this script.
#
# The following variables exported from environment will be used.
# If not set then values previously saved in domain.conf file are used.
#
# Only a username is required.  All others are optional.
#
# export DEPLOY_SSH_CPANEL_USER="admin"                # required
# export DEPLOY_SSH_CPANEL_CMD="ssh -i /path/to/key"   # defaults to ssh
# export DEPLOY_SSH_CPANEL_SERVER="server.example.com" # defaults to domain name
# export DEPLOY_SSH_CPANEL_UAPIUSER="cPanelUserName"   # defaults to DEPLOY_SSH_CPANEL_USER
########  Public functions #####################

#domain keyfile certfile cafile fullchain
ssh_cpanel_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _cmdstr=""

  if [ -f "$DOMAIN_CONF" ]; then
    # shellcheck disable=SC1090
    . "$DOMAIN_CONF"
  fi

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  # USER is required to login by SSH to remote host.
  if [ -z "$DEPLOY_SSH_CPANEL_USER" ]; then
    if [ -z "$Le_Deploy_ssh_cpanel_user" ]; then
      _err "DEPLOY_SSH_CPANEL_USER not defined."
      return 1
    fi
  else
    Le_Deploy_ssh_cpanel_user="$DEPLOY_SSH_CPANEL_USER"
    _savedomainconf Le_Deploy_ssh_cpanel_user "$Le_Deploy_ssh_cpanel_user"
  fi

  # UAPIUSER is optional. If not provided then use DEPLOY_SSH_CPANEL_USER
  if [ -z "$DEPLOY_SSH_CPANEL_UAPIUSER" ]; then
    if [ -z "$Le_Deploy_ssh_cpanel_uapiuser" ]; then
      Le_Deploy_ssh_cpanel_uapiuser="$Le_Deploy_ssh_cpanel_user"
    fi
  else
    Le_Deploy_ssh_cpanel_uapiuser="$DEPLOY_SSH_CPANEL_UAPIUSER"
    _savedomainconf Le_Deploy_ssh_cpanel_uapiuser "$Le_Deploy_ssh_cpanel_uapiuser"
  fi

  # SERVER is optional. If not provided then use _cdomain
  if [ -n "$DEPLOY_SSH_CPANEL_SERVER" ]; then
    Le_Deploy_ssh_cpanel_server="$DEPLOY_SSH_CPANEL_SERVER"
    _savedomainconf Le_Deploy_ssh_cpanel_server "$Le_Deploy_ssh_cpanel_server"
  elif [ -z "$Le_Deploy_ssh_cpanel_server" ]; then
    Le_Deploy_ssh_cpanel_server="$_cdomain"
  fi

  # CMD is optional. If not provided then use ssh
  if [ -n "$DEPLOY_SSH_CPANEL_CMD" ]; then
    Le_Deploy_ssh_cpanel_cmd="$DEPLOY_SSH_CPANEL_CMD"
    _savedomainconf Le_Deploy_ssh_cpanel_cmd "$Le_Deploy_ssh_cpanel_cmd"
  elif [ -z "$Le_Deploy_ssh_cpanel_cmd" ]; then
    Le_Deploy_ssh_cpanel_cmd="ssh"
  fi

  _info "Deploy certificates to remote server $Le_Deploy_ssh_cpanel_user@$Le_Deploy_ssh_cpanel_server"

  # read cert and key files and urlencode both
  _info "URL Encode Certificate..."
  _cert=$(_url_encode <"$_ccert")

  _info "URL Encode Key..."
  _key=$(_url_encode <"$_ckey")

  _secure_debug _cert "$_cert"
  _secure_debug _key "$_key"

  if [ "$Le_Deploy_ssh_cpanel_uapiuser" = "$Le_Deploy_ssh_cpanel_user" ]; then
    _cmdstr="uapi SSL install_ssl domain=\"$_cdomain\" cert=\"$_cert\" key=\"$_key\""
  else
    _cmdstr="uapi --user=\"$Le_Deploy_ssh_cpanel_uapiuser\" SSL install_ssl domain=\"$_cdomain\" cert=\"$_cert\" key=\"$_key\""
  fi

  _secure_debug "Remote commands to execute: " "$_cmdstr"
  _info "Submitting sequence of commands to remote server by ssh"
  # quotations in bash cmd below intended.  Squash travis spellcheck error
  # shellcheck disable=SC2029
  $Le_Deploy_ssh_cpanel_cmd -T "$Le_Deploy_ssh_cpanel_user@$Le_Deploy_ssh_cpanel_server" sh -c "'$_cmdstr'"
  _ret="$?"

  if [ "$_ret" != "0" ]; then
    _err "Error code $_ret returned from $Le_Deploy_ssh_cpanel_cmd"
  fi

  _error_response="status: 0"
  if test "${_ret#*$_error_response}" != "$_ret"; then
    _err "Error in deploying certificate:"
    _err "$_ret"
    return 1
  fi

  _debug ret "$_ret"
  _info "Certificate successfully deployed"
  return 0
}
