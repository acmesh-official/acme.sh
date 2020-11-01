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
# export DEPLOY_SSH_CMD=""  # defaults to "ssh -T"
# export DEPLOY_SSH_USER="admin"  # required
# export DEPLOY_SSH_SERVER="qnap"  # defaults to domain name
# export DEPLOY_SSH_KEYFILE="/etc/stunnel/stunnel.pem"
# export DEPLOY_SSH_CERTFILE="/etc/stunnel/stunnel.pem"
# export DEPLOY_SSH_CAFILE="/etc/stunnel/uca.pem"
# export DEPLOY_SSH_FULLCHAIN=""
# export DEPLOY_SSH_REMOTE_CMD="/etc/init.d/stunnel.sh restart"
# export DEPLOY_SSH_BACKUP=""  # yes or no, default to yes or previously saved value
# export DEPLOY_SSH_BACKUP_PATH=".acme_ssh_deploy"  # path on remote system. Defaults to .acme_ssh_deploy
# export DEPLOY_SSH_MULTI_CALL=""  # yes or no, default to no or previously saved value
#
########  Public functions #####################

#domain keyfile certfile cafile fullchain
ssh_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _deploy_ssh_servers=""

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
    Le_Deploy_ssh_cmd="ssh -T"
  fi

  # BACKUP is optional. If not provided then default to previously saved value or yes.
  if [ "$DEPLOY_SSH_BACKUP" = "no" ]; then
    Le_Deploy_ssh_backup="no"
  elif [ -z "$Le_Deploy_ssh_backup" ] || [ "$DEPLOY_SSH_BACKUP" = "yes" ]; then
    Le_Deploy_ssh_backup="yes"
  fi
  _savedomainconf Le_Deploy_ssh_backup "$Le_Deploy_ssh_backup"

  # BACKUP_PATH is optional. If not provided then default to previously saved value or .acme_ssh_deploy
  if [ -n "$DEPLOY_SSH_BACKUP_PATH" ]; then
    Le_Deploy_ssh_backup_path="$DEPLOY_SSH_BACKUP_PATH"
  elif [ -z "$Le_Deploy_ssh_backup_path" ]; then
    Le_Deploy_ssh_backup_path=".acme_ssh_deploy"
  fi
  _savedomainconf Le_Deploy_ssh_backup_path "$Le_Deploy_ssh_backup_path"

  # MULTI_CALL is optional. If not provided then default to previously saved
  # value (which may be undefined... equivalent to "no").
  if [ "$DEPLOY_SSH_MULTI_CALL" = "yes" ]; then
    Le_Deploy_ssh_multi_call="yes"
    _savedomainconf Le_Deploy_ssh_multi_call "$Le_Deploy_ssh_multi_call"
  elif [ "$DEPLOY_SSH_MULTI_CALL" = "no" ]; then
    Le_Deploy_ssh_multi_call=""
    _cleardomainconf Le_Deploy_ssh_multi_call
  fi

  _deploy_ssh_servers=$Le_Deploy_ssh_server
  for Le_Deploy_ssh_server in $_deploy_ssh_servers; do
    _ssh_deploy
  done
}

_ssh_deploy() {
  _err_code=0
  _cmdstr=""
  _backupprefix=""
  _backupdir=""

  _info "Deploy certificates to remote server $Le_Deploy_ssh_user@$Le_Deploy_ssh_server"
  if [ "$Le_Deploy_ssh_multi_call" = "yes" ]; then
    _info "Using MULTI_CALL mode... Required commands sent in multiple calls to remote host"
  else
    _info "Required commands batched and sent in single call to remote host"
  fi

  if [ "$Le_Deploy_ssh_backup" = "yes" ]; then
    _backupprefix="$Le_Deploy_ssh_backup_path/$_cdomain-backup"
    _backupdir="$_backupprefix-$(_utc_date | tr ' ' '-')"
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
    if [ "$Le_Deploy_ssh_multi_call" = "yes" ]; then
      if ! _ssh_remote_cmd "$_cmdstr"; then
        return $_err_code
      fi
      _cmdstr=""
    fi
  fi

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
    if [ "$Le_Deploy_ssh_multi_call" = "yes" ]; then
      if ! _ssh_remote_cmd "$_cmdstr"; then
        return $_err_code
      fi
      _cmdstr=""
    fi
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
    if [ "$Le_Deploy_ssh_multi_call" = "yes" ]; then
      if ! _ssh_remote_cmd "$_cmdstr"; then
        return $_err_code
      fi
      _cmdstr=""
    fi
  fi

  # CAFILE is optional.
  # If provided then CA intermediate certificate will be copied or appended to provided filename.
  if [ -n "$DEPLOY_SSH_CAFILE" ]; then
    Le_Deploy_ssh_cafile="$DEPLOY_SSH_CAFILE"
    _savedomainconf Le_Deploy_ssh_cafile "$Le_Deploy_ssh_cafile"
  fi
  if [ -n "$Le_Deploy_ssh_cafile" ]; then
    _pipe=">"
    if [ "$Le_Deploy_ssh_cafile" = "$Le_Deploy_ssh_keyfile" ] ||
      [ "$Le_Deploy_ssh_cafile" = "$Le_Deploy_ssh_certfile" ]; then
      # if filename is same as previous file then append.
      _pipe=">>"
    elif [ "$Le_Deploy_ssh_backup" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $Le_Deploy_ssh_cafile $_backupdir >/dev/null;"
    fi
    # copy new certificate into file.
    _cmdstr="$_cmdstr echo \"$(cat "$_cca")\" $_pipe $Le_Deploy_ssh_cafile;"
    _info "will copy CA file to remote file $Le_Deploy_ssh_cafile"
    if [ "$Le_Deploy_ssh_multi_call" = "yes" ]; then
      if ! _ssh_remote_cmd "$_cmdstr"; then
        return $_err_code
      fi
      _cmdstr=""
    fi
  fi

  # FULLCHAIN is optional.
  # If provided then fullchain certificate will be copied or appended to provided filename.
  if [ -n "$DEPLOY_SSH_FULLCHAIN" ]; then
    Le_Deploy_ssh_fullchain="$DEPLOY_SSH_FULLCHAIN"
    _savedomainconf Le_Deploy_ssh_fullchain "$Le_Deploy_ssh_fullchain"
  fi
  if [ -n "$Le_Deploy_ssh_fullchain" ]; then
    _pipe=">"
    if [ "$Le_Deploy_ssh_fullchain" = "$Le_Deploy_ssh_keyfile" ] ||
      [ "$Le_Deploy_ssh_fullchain" = "$Le_Deploy_ssh_certfile" ] ||
      [ "$Le_Deploy_ssh_fullchain" = "$Le_Deploy_ssh_cafile" ]; then
      # if filename is same as previous file then append.
      _pipe=">>"
    elif [ "$Le_Deploy_ssh_backup" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $Le_Deploy_ssh_fullchain $_backupdir >/dev/null;"
    fi
    # copy new certificate into file.
    _cmdstr="$_cmdstr echo \"$(cat "$_cfullchain")\" $_pipe $Le_Deploy_ssh_fullchain;"
    _info "will copy fullchain to remote file $Le_Deploy_ssh_fullchain"
    if [ "$Le_Deploy_ssh_multi_call" = "yes" ]; then
      if ! _ssh_remote_cmd "$_cmdstr"; then
        return $_err_code
      fi
      _cmdstr=""
    fi
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
    if [ "$Le_Deploy_ssh_multi_call" = "yes" ]; then
      if ! _ssh_remote_cmd "$_cmdstr"; then
        return $_err_code
      fi
      _cmdstr=""
    fi
  fi

  # if commands not all sent in multiple calls then all commands sent in a single SSH call now...
  if [ -n "$_cmdstr" ]; then
    if ! _ssh_remote_cmd "$_cmdstr"; then
      return $_err_code
    fi
  fi
  return 0
}

#cmd
_ssh_remote_cmd() {
  _cmd="$1"
  _secure_debug "Remote commands to execute: $_cmd"
  _info "Submitting sequence of commands to remote server by ssh"
  # quotations in bash cmd below intended.  Squash travis spellcheck error
  # shellcheck disable=SC2029
  $Le_Deploy_ssh_cmd "$Le_Deploy_ssh_user@$Le_Deploy_ssh_server" sh -c "'$_cmd'"
  _err_code="$?"

  if [ "$_err_code" != "0" ]; then
    _err "Error code $_err_code returned from ssh"
  fi

  return $_err_code
}
