#!/usr/bin/env sh

# Script to deploy certificates to remote server by SSH
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
# The following examples are for QNAP NAS running QTS 4.2
# export DEPLOY_SSH_CMD=""  # defaults to ssh
# export DEPLOY_SSH_USER="admin"  # required
# export DEPLOY_SSH_SERVER="qnap"  # defaults to domain name
# export DEPLOY_SSH_KEYFILE="/etc/stunnel/stunnel.pem"
# export DEPLOY_SSH_CERTFILE="/etc/stunnel/stunnel.pem"
# export DEPLOY_SSH_CAFILE="/etc/stunnel/uca.pem"
# export DEPLOY_SSH_FULLCHAIN=""
# export DEPLOY_SSH_REMOTE_CMD="/etc/init.d/stunnel.sh restart"
# export DEPLOY_SSH_BACKUP=""  # yes or no, default to yes
#
########  Public functions #####################

#domain keyfile certfile cafile fullchain
ssh_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _cmdstr=""
  _homedir='~'
  _backupprefix="$_homedir/.acme_ssh_deploy/$_cdomain-backup"
  _backupdir="$_backupprefix-$(_utc_date | tr ' ' '-')"

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
  if [ -z "$DEPLOY_SSH_USER" ]; then
    if [ -z "$Le_Deploy_ssh_user" ]; then
      _err "DEPLOY_SSH_USER not defined."
      return 1
    fi
  else
    Le_Deploy_ssh_user="$DEPLOY_SSH_USER"
    _savedomainconf Le_Deploy_ssh_user "$Le_Deploy_ssh_user"
  fi

  # SERVER is optional. If not provided then use _cdomain
  if [ -n "$DEPLOY_SSH_SERVER" ]; then
    Le_Deploy_ssh_server="$DEPLOY_SSH_SERVER"
    _savedomainconf Le_Deploy_ssh_server "$Le_Deploy_ssh_server"
  elif [ -z "$Le_Deploy_ssh_server" ]; then
    Le_Deploy_ssh_server="$_cdomain"
  fi

  # CMD is optional. If not provided then use ssh
  if [ -n "$DEPLOY_SSH_CMD" ]; then
    Le_Deploy_ssh_cmd="$DEPLOY_SSH_CMD"
    _savedomainconf Le_Deploy_ssh_cmd "$Le_Deploy_ssh_cmd"
  elif [ -z "$Le_Deploy_ssh_cmd" ]; then
    Le_Deploy_ssh_cmd="ssh"
  fi

  # BACKUP is optional. If not provided then default to yes
  if [ "$DEPLOY_SSH_BACKUP" = "no" ]; then
    Le_Deploy_ssh_backup="no"
  elif [ -z "$Le_Deploy_ssh_backup" ]; then
    Le_Deploy_ssh_backup="yes"
  fi
  _savedomainconf Le_Deploy_ssh_backup "$Le_Deploy_ssh_backup"

  _info "Deploy certificates to remote server $Le_Deploy_ssh_user@$Le_Deploy_ssh_server"

  # KEYFILE is optional.
  # If provided then private key will be copied to provided filename.
  if [ -n "$DEPLOY_SSH_KEYFILE" ]; then
    Le_Deploy_ssh_keyfile="$DEPLOY_SSH_KEYFILE"
    _savedomainconf Le_Deploy_ssh_keyfile "$Le_Deploy_ssh_keyfile"
  fi
  if [ -n "$Le_Deploy_ssh_keyfile" ]; then
    if [ "$Le_Deploy_ssh_backup" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $Le_Deploy_ssh_keyfile $_backupdir >/dev/null;"
    fi
    # copy new certificate into file.
    _cmdstr="$_cmdstr echo \"$(cat "$_ckey")\" > $Le_Deploy_ssh_keyfile;"
    _info "will copy private key to remote file $Le_Deploy_ssh_keyfile"
  fi

  # CERTFILE is optional.
  # If provided then certificate will be copied or appended to provided filename.
  if [ -n "$DEPLOY_SSH_CERTFILE" ]; then
    Le_Deploy_ssh_certfile="$DEPLOY_SSH_CERTFILE"
    _savedomainconf Le_Deploy_ssh_certfile "$Le_Deploy_ssh_certfile"
  fi
  if [ -n "$Le_Deploy_ssh_certfile" ]; then
    _pipe=">"
    if [ "$Le_Deploy_ssh_certfile" = "$Le_Deploy_ssh_keyfile" ]; then
      # if filename is same as previous file then append.
      _pipe=">>"
    elif [ "$Le_Deploy_ssh_backup" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $Le_Deploy_ssh_certfile $_backupdir >/dev/null;"
    fi
    # copy new certificate into file.
    _cmdstr="$_cmdstr echo \"$(cat "$_ccert")\" $_pipe $Le_Deploy_ssh_certfile;"
    _info "will copy certificate to remote file $Le_Deploy_ssh_certfile"
  fi

  # CAFILE is optional.
  # If provided then CA intermediate certificate will be copied or appended to provided filename.
  if [ -n "$DEPLOY_SSH_CAFILE" ]; then
    Le_Deploy_ssh_cafile="$DEPLOY_SSH_CAFILE"
    _savedomainconf Le_Deploy_ssh_cafile "$Le_Deploy_ssh_cafile"
  fi
  if [ -n "$Le_Deploy_ssh_cafile" ]; then
    _pipe=">"
    if [ "$Le_Deploy_ssh_cafile" = "$Le_Deploy_ssh_keyfile" ] \
      || [ "$Le_Deploy_ssh_cafile" = "$Le_Deploy_ssh_certfile" ]; then
      # if filename is same as previous file then append.
      _pipe=">>"
    elif [ "$Le_Deploy_ssh_backup" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $Le_Deploy_ssh_cafile $_backupdir >/dev/null;"
    fi
    # copy new certificate into file.
    _cmdstr="$_cmdstr echo \"$(cat "$_cca")\" $_pipe $Le_Deploy_ssh_cafile;"
    _info "will copy CA file to remote file $Le_Deploy_ssh_cafile"
  fi

  # FULLCHAIN is optional.
  # If provided then fullchain certificate will be copied or appended to provided filename.
  if [ -n "$DEPLOY_SSH_FULLCHAIN" ]; then
    Le_Deploy_ssh_fullchain="$DEPLOY_SSH_FULLCHAIN"
    _savedomainconf Le_Deploy_ssh_fullchain "$Le_Deploy_ssh_fullchain"
  fi
  if [ -n "$Le_Deploy_ssh_fullchain" ]; then
    _pipe=">"
    if [ "$Le_Deploy_ssh_fullchain" = "$Le_Deploy_ssh_keyfile" ] \
      || [ "$Le_Deploy_ssh_fullchain" = "$Le_Deploy_ssh_certfile" ] \
      || [ "$Le_Deploy_ssh_fullchain" = "$Le_Deploy_ssh_cafile" ]; then
      # if filename is same as previous file then append.
      _pipe=">>"
    elif [ "$Le_Deploy_ssh_backup" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $Le_Deploy_ssh_fullchain $_backupdir >/dev/null;"
    fi
    # copy new certificate into file.
    _cmdstr="$_cmdstr echo \"$(cat "$_cfullchain")\" $_pipe $Le_Deploy_ssh_fullchain;"
    _info "will copy fullchain to remote file $Le_Deploy_ssh_fullchain"
  fi

  # REMOTE_CMD is optional.
  # If provided then this command will be executed on remote host.
  if [ -n "$DEPLOY_SSH_REMOTE_CMD" ]; then
    Le_Deploy_ssh_remote_cmd="$DEPLOY_SSH_REMOTE_CMD"
    _savedomainconf Le_Deploy_ssh_remote_cmd "$Le_Deploy_ssh_remote_cmd"
  fi
  if [ -n "$Le_Deploy_ssh_remote_cmd" ]; then
    _cmdstr="$_cmdstr $Le_Deploy_ssh_remote_cmd;"
    _info "Will execute remote command $Le_Deploy_ssh_remote_cmd"
  fi

  if [ -z "$_cmdstr" ]; then
    _err "No remote commands to excute. Failed to deploy certificates to remote server"
    return 1
  elif [ "$Le_Deploy_ssh_backup" = "yes" ]; then
    # run cleanup on the backup directory, erase all older
    # than 180 days (15552000 seconds).
    _cmdstr="{ now=\"\$(date -u +%s)\"; for fn in $_backupprefix*; \
do if [ -d \"\$fn\" ] && [ \"\$(expr \$now - \$(date -ur \$fn +%s) )\" -ge \"15552000\" ]; \
then rm -rf \"\$fn\"; echo \"Backup \$fn deleted as older than 180 days\"; fi; done; }; $_cmdstr"
    # Alternate version of above... _cmdstr="find $_backupprefix* -type d -mtime +180 2>/dev/null | xargs rm -rf; $_cmdstr"
    # Create our backup directory for overwritten cert files.
    _cmdstr="mkdir -p $_backupdir; $_cmdstr"
    _info "Backup of old certificate files will be placed in remote directory $_backupdir"
    _info "Backup directories erased after 180 days."
  fi

  _secure_debug "Remote commands to execute: " "$_cmdstr"
  _info "Submitting sequence of commands to remote server by ssh"
  # quotations in bash cmd below intended.  Squash travis spellcheck error
  # shellcheck disable=SC2029
  $Le_Deploy_ssh_cmd -T "$Le_Deploy_ssh_user@$Le_Deploy_ssh_server" sh -c "'$_cmdstr'"
  _ret="$?"

  if [ "$_ret" != "0" ]; then
    _err "Error code $_ret returned from $Le_Deploy_ssh_cmd"
  fi

  return $_ret
}
