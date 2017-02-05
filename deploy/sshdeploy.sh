#!/usr/bin/env sh

# Script to deploy certificates to remote server by SSH
# Note that SSH must be able to login to remote host without a password...
# SSH Keys must have been exchanged with the remote host.  Validate and
# test that you can login to USER@URL from the host running acme.sh before
# using this script.
#
# The following variables exported from environment will be used.
# If not set then values previously saved in domain.conf file are used.
#
# Only a username is required.  All others are optional.
#
# The following examples are for QNAP NAS running QTS 4.2 
# export ACME_DEPLOY_SSH_USER="admin"
# export ACME_DEPLOY_SSH_URL="qnap"
# export ACME_DEPLOY_SSH_SERVICE_STOP=""
# export ACME_DEPLOY_SSH_KEYFILE="/etc/stunnel/stunnel.pem"
# export ACME_DEPLOY_SSH_CERTFILE="/etc/stunnel/stunnel.pem"
# export ACME_DEPLOY_SSH_CAFILE="/etc/stunnel/uca.pem"
# export ACME_DEPLOY_SSH_FULLCHAIN=""
# export ACME_DEPLOY_SSH_REMOTE_CMD="/etc/init.d/stunnel.sh restart"
# export ACME_DEPLOY_SSH_SERVICE_START=""

########  Public functions #####################

#domain keyfile certfile cafile fullchain
sshdeploy_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _cmdstr=""
  _homedir='~'
  _homedir="$_homedir/.acme_ssh_deploy"
  _backupdir="$_homedir/certs-backup-$(date +%Y%m%d%H%M%S)"

  if [ -z "$DOMAIN_CONF" ]; then
    DOMAIN_CONF=""
  fi
  if [ ! -f "$DOMAIN_CONF" ]; then
    _err "$DOMAIN_CONF does not exist."
    return 1
  fi

  . "$DOMAIN_CONF"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  # USER is required to login by SSH to remote host.
  if [ -z "$ACME_DEPLOY_SSH_USER" ]; then
    if [ -z "$Le_Deploy_ssh_user" ]; then
      _err "ACME_DEPLOY_SSH_USER not defined."
      return 1
    fi
  else
    Le_Deploy_ssh_user="$ACME_DEPLOY_SSH_USER"
    _savedomainconf Le_Deploy_ssh_user "$Le_Deploy_ssh_user"
  fi

  # URL is optional.  If not provided then use _cdomain
  if [ -n "$ACME_DEPLOY_SSH_URL" ]; then
    Le_Deploy_ssh_url="$ACME_DEPLOY_SSH_URL"
    _savedomainconf Le_Deploy_ssh_url "$Le_Deploy_ssh_url"
  elif [ -z "$Le_Deploy_ssh_url" ]; then
    Le_Deploy_ssh_url="$_cdomain"
  fi

  _info "Deploy certificates to remote server $Le_Deploy_ssh_user@$Le_Deploy_ssh_url"

  # SERVICE_STOP is optional.
  # If provided then this command will be executed on remote host.
  if [ -n "$ACME_DEPLOY_SSH_SERVICE_STOP" ]; then
    Le_Deploy_ssh_service_stop="$ACME_DEPLOY_SSH_SERVICE_STOP"
    _savedomainconf Le_Deploy_ssh_service_stop "$Le_Deploy_ssh_service_stop"
  fi
  if [ -n "$Le_Deploy_ssh_service_stop" ]; then
    _cmdstr="$_cmdstr $Le_Deploy_ssh_service_stop ;"
    _info "Will stop remote service with command $Le_Deploy_ssh_service_stop"
  fi

  # KEYFILE is optional.
  # If provided then private key will be copied to provided filename.
  if [ -n "$ACME_DEPLOY_SSH_KEYFILE" ]; then
    Le_Deploy_ssh_keyfile="$ACME_DEPLOY_SSH_KEYFILE"
    _savedomainconf Le_Deploy_ssh_keyfile "$Le_Deploy_ssh_keyfile"
  fi
  if [ -n "$Le_Deploy_ssh_keyfile" ]; then
    # backup file we are about to overwrite.
    _cmdstr="$_cmdstr cp $Le_Deploy_ssh_keyfile $_backupdir ;"
    # copy new certificate into file.
    _cmdstr="$_cmdstr echo \"$(cat $_ckey)\" > $Le_Deploy_ssh_keyfile ;"
    _info "will copy private key to remote file $Le_Deploy_ssh_keyfile"
  fi

  # CERTFILE is optional.
  # If provided then private key will be copied or appended to provided filename.
  if [ -n "$ACME_DEPLOY_SSH_CERTFILE" ]; then
    Le_Deploy_ssh_certfile="$ACME_DEPLOY_SSH_CERTFILE"
    _savedomainconf Le_Deploy_ssh_certfile "$Le_Deploy_ssh_certfile"
  fi
  if [ -n "$Le_Deploy_ssh_certfile" ]; then
    if [ "$Le_Deploy_ssh_certfile" = "$Le_Deploy_ssh_keyfile" ]; then
      # if filename is same as that provided for private key then append.
      _cmdstr="$_cmdstr echo \"$(cat $_ccert)\" >> $Le_Deploy_ssh_certfile ;"
      _info "will append certificate to same file"
    else
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $Le_Deploy_ssh_certfile $_backupdir ;"
      # copy new certificate into file.
      _cmdstr="$_cmdstr echo \"$(cat $_ccert)\" > $Le_Deploy_ssh_certfile ;"
      _info "will copy certificate to remote file $Le_Deploy_ssh_certfile"
    fi
  fi

  # CAFILE is optional.
  # If provided then CA intermediate certificate will be copied to provided filename.
  if [ -n "$ACME_DEPLOY_SSH_CAFILE" ]; then
    Le_Deploy_ssh_cafile="$ACME_DEPLOY_SSH_CAFILE"
    _savedomainconf Le_Deploy_ssh_cafile "$Le_Deploy_ssh_cafile"
  fi
  if [ -n "$Le_Deploy_ssh_cafile" ]; then
    # backup file we are about to overwrite.
    _cmdstr="$_cmdstr cp $Le_Deploy_ssh_cafile $_backupdir ;"
    # copy new certificate into file.
    _cmdstr="$_cmdstr echo \"$(cat $_cca)\" > $Le_Deploy_ssh_cafile ;"
    _info "will copy CA file to remote file $Le_Deploy_ssh_cafile"
  fi

  # FULLCHAIN is optional.
  # If provided then fullchain certificate will be copied to provided filename.
  if [ -n "$ACME_DEPLOY_SSH_FULLCHAIN" ]; then
    Le_Deploy_ssh_fullchain="$ACME_DEPLOY_SSH_FULLCHAIN"
    _savedomainconf Le_Deploy_ssh_fullchain "$Le_Deploy_ssh_fullchain"
  fi
  if [ -n "$Le_Deploy_ssh_fullchain" ]; then
    # backup file we are about to overwrite.
    _cmdstr="$_cmdstr cp $Le_Deploy_ssh_fullchain $_backupdir ;"
    # copy new certificate into file.
    _cmdstr="$_cmdstr echo \"$(cat $_cfullchain)\" > $Le_Deploy_ssh_fullchain ;"
    _info "will copy full chain to remote file $Le_Deploy_ssh_fullchain"
  fi

  # REMOTE_CMD is optional.
  # If provided then this command will be executed on remote host.
  # A 2 second delay is inserted to allow system to stabalize after
  # executing a service stop.
  if [ -n "$ACME_DEPLOY_SSH_REMOTE_CMD" ]; then
    Le_Deploy_ssh_remote_cmd="$ACME_DEPLOY_SSH_REMOTE_CMD"
    _savedomainconf Le_Deploy_ssh_remote_cmd "$Le_Deploy_ssh_remote_cmd"
  fi
  if [ -n "$Le_Deploy_ssh_remote_cmd" ]; then
    if [ -n "$Le_Deploy_ssh_service_stop" ]; then
      _cmdstr="$_cmdstr sleep 2 ;"
    fi
    _cmdstr="$_cmdstr $Le_Deploy_ssh_remote_cmd ;"
    _info "Will execute remote command $Le_Deploy_ssh_remote_cmd"
  fi

  # SERVICE_START is optional.
  # If provided then this command will be executed on remote host.
  # A 2 second delay is inserted to allow system to stabalize after
  # executing a service stop or previous command.
  if [ -n "$ACME_DEPLOY_SSH_SERVICE_START" ]; then
    Le_Deploy_ssh_service_start="$ACME_DEPLOY_SSH_SERVICE_START"
    _savedomainconf Le_Deploy_ssh_service_start "$Le_Deploy_ssh_service_start"
  fi
  if [ -n "$Le_Deploy_ssh_service_start" ]; then
    if [ -n "$Le_Deploy_ssh_service_stop" ] || [ -n "$Le_Deploy_ssh_remote_cmd" ]; then
      _cmdstr="$_cmdstr sleep 2 ;"
    fi
    _cmdstr="$_cmdstr $Le_Deploy_ssh_service_start ;"
    _info "Will start remote service with command $Le_Deploy_ssh_remote_cmd"
  fi

  if [ -z "$_cmdstr" ]; then
    _err "No remote commands to excute. Failed to deploy certificates to remote server"
    return 1
  else
    # something to execute.
    # run cleanup on the backup directory, erase all older than 180 days.
    _cmdstr="find $_homedir/* -type d -mtime +180 2>/dev/null | xargs rm -rf ; $_cmdstr"
    # Create our backup directory for overwritten cert files.
    _cmdstr="mkdir -p $_backupdir ; $_cmdstr"
    _info "Backup of old certificate files will be placed in remote directory $_backupdir"
    _info "Backup directories erased after 180 days."
  fi

  _debug "Remote commands to execute: $_cmdstr"
  _info "Submitting sequence of commands to remote server by ssh"
  ssh -T "$Le_Deploy_ssh_user@$Le_Deploy_ssh_url" bash -c "'$_cmdstr'"

  return 0
}
