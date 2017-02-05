#!/usr/bin/env sh

#Here is a script to deploy certificates to remote server by ssh
#This file name is "sshdeploy.sh"
#So, here must be a method   sshdeploy_deploy()
#Which will be called by acme.sh to deploy the cert
#returns 0 means success, otherwise error.

# The following variables exported from environment will be used.
# If not set then values previously saved in domain.conf file are used.
#
# export ACME_DEPLOY_SSH_URL="admin@qnap"
# export ACME_DEPLOY_SSH_SERVICE_STOP="/etc/init.d/stunnel.sh stop"
# export ACME_DEPLOY_SSH_KEYFILE="/etc/stunnel/stunnel.pem"
# export ACME_DEPLOY_SSH_CERTFILE="/etc/stunnel/stunnel.pem"
# export ACME_DEPLOY_SSH_CAFILE="/etc/stunnel/uca.pem"
# export ACME_DEPLOY_SSH_FULLCHAIN=""
# export ACME_DEPLOY_SSH_REMOTE_CMD="/etc/init.d/stunnel.sh restart"
# export ACME_DEPLOY_SSH_SERVICE_START="/etc/init.d/stunnel.sh stop"

. "$DOMAIN_CONF"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
sshdeploy_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _cmdstr="{"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  if [ -z "$ACME_DEPLOY_SSH_URL" ]; then
    if [ -z "$Le_Deploy_ssh_url" ]; then
      _err "ACME_DEPLOY_SSH_URL not defined."
      return 1
    fi
  else
    Le_Deploy_ssh_url="$ACME_DEPLOY_SSH_URL"
    _savedomainconf Le_Deploy_ssh_url "$Le_Deploy_ssh_url"
  fi
  
  _info "Deploy certificates to remote server $Le_Deploy_ssh_url"

  if [ -n "$ACME_DEPLOY_SSH_SERVICE_STOP" ]; then
    Le_Deploy_ssh_service_stop="$ACME_DEPLOY_SSH_SERVICE_STOP"
    _savedomainconf Le_Deploy_ssh_service_stop "$Le_Deploy_ssh_service_stop"
  fi
  if [ -n "$Le_Deploy_ssh_service_stop" ]; then
    _cmdstr="$_cmdstr $Le_Deploy_ssh_service_stop ;"
    _info "Will stop remote service with command $Le_Deploy_ssh_service_stop"
  fi

  if [ -n "$ACME_DEPLOY_SSH_KEYFILE" ]; then
    Le_Deploy_ssh_keyfile="$ACME_DEPLOY_SSH_KEYFILE"
    _savedomainconf Le_Deploy_ssh_keyfile "$Le_Deploy_ssh_keyfile"
  fi
  if [ -n "$Le_Deploy_ssh_keyfile" ]; then
    _cmdstr="$_cmdstr echo \"$(cat $_ckey)\" > $Le_Deploy_ssh_keyfile ;"
    _info "will copy private key to remote file $Le_Deploy_ssh_keyfile"
  fi

  if [ -n "$ACME_DEPLOY_SSH_CERTFILE" ]; then
    Le_Deploy_ssh_certfile="$ACME_DEPLOY_SSH_CERTFILE"
    _savedomainconf Le_Deploy_ssh_certfile "$Le_Deploy_ssh_certfile"
  fi
  if [ -n "$Le_Deploy_ssh_certfile" ]; then
    if [ "$Le_Deploy_ssh_certfile" = "$Le_Deploy_ssh_keyfile" ]; then
      _cmdstr="$_cmdstr echo \"$(cat $_ccert)\" >> $Le_Deploy_ssh_certfile ;"
      _info "will append certificate to same file"
    else
      _cmdstr="$_cmdstr echo \"$(cat $_ccert)\" > $Le_Deploy_ssh_certfile ;"
      _info "will copy certificate to remote file $Le_Deploy_ssh_certfile"
    fi
  fi

  if [ -n "$ACME_DEPLOY_SSH_CAFILE" ]; then
    Le_Deploy_ssh_cafile="$ACME_DEPLOY_SSH_CAFILE"
    _savedomainconf Le_Deploy_ssh_cafile "$Le_Deploy_ssh_cafile"
  fi
  if [ -n "$Le_Deploy_ssh_cafile" ]; then
    _cmdstr="$_cmdstr echo \"$(cat $_cca)\" > $Le_Deploy_ssh_cafile ;"
    _info "will copy CA file to remote file $Le_Deploy_ssh_cafile"
  fi

  if [ -n "$ACME_DEPLOY_SSH_FULLCHAIN" ]; then
    Le_Deploy_ssh_fullchain="$ACME_DEPLOY_SSH_FULLCHAIN"
    _savedomainconf Le_Deploy_ssh_fullchain "$Le_Deploy_ssh_fullchain"
  fi
  if [ -n "$Le_Deploy_ssh_fullchain" ]; then
    _cmdstr="$_cmdstr echo \"$(cat $_cfullchain)\" > $Le_Deploy_ssh_fullchain ;"
    _info "will copy full chain to remote file $Le_Deploy_ssh_fullchain"
  fi

  if [ -n "$ACME_DEPLOY_SSH_REMOTE_CMD" ]; then
    Le_Deploy_ssh_remote_cmd="$ACME_DEPLOY_SSH_REMOTE_CMD"
    _savedomainconf Le_Deploy_ssh_remote_cmd "$Le_Deploy_ssh_remote_cmd"
  fi
  if [ -n "$Le_Deploy_ssh_remote_cmd" ]; then
    _cmdstr="$_cmdstr sleep 2 ; $Le_Deploy_ssh_remote_cmd ;"
    _info "Will sleep 2 seconds then execute remote command $Le_Deploy_ssh_remote_cmd"
  fi

  if [ -n "$ACME_DEPLOY_SSH_SERVICE_START" ]; then
    Le_Deploy_ssh_service_start="$ACME_DEPLOY_SSH_SERVICE_START"
    _savedomainconf Le_Deploy_ssh_service_start "$Le_Deploy_ssh_service_start"
  fi
  if [ -n "$Le_Deploy_ssh_service_start" ]; then
    _cmdstr="$_cmdstr sleep 2 ; $Le_Deploy_ssh_service_start ;"
    _info "Will sleep 2 seconds then start remote service with command $Le_Deploy_ssh_remote_cmd"
  fi

  _cmdstr="$_cmdstr }"

  _debug "Remote command to execute: $_cmdstr"

  _info "Submitting sequence of commands to remote server by ssh"
  ssh -T "$Le_Deploy_ssh_url" bash -c "'$_cmdstr'"

  return 0
}
