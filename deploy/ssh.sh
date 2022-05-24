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
# export DEPLOY_SSH_SERVER="host1 host2:8022 192.168.0.1:9022"  # defaults to domain name, support multiple servers with optional port
# export DEPLOY_SSH_KEYFILE="/etc/stunnel/stunnel.pem"
# export DEPLOY_SSH_CERTFILE="/etc/stunnel/stunnel.pem"
# export DEPLOY_SSH_CAFILE="/etc/stunnel/uca.pem"
# export DEPLOY_SSH_FULLCHAIN=""
# export DEPLOY_SSH_REMOTE_CMD="/etc/init.d/stunnel.sh restart"
# export DEPLOY_SSH_BACKUP=""  # yes or no, default to yes or previously saved value
# export DEPLOY_SSH_BACKUP_PATH=".acme_ssh_deploy"  # path on remote system. Defaults to .acme_ssh_deploy
# export DEPLOY_SSH_MULTI_CALL=""  # yes or no, default to no or previously saved value
# export DEPLOY_SSH_USE_SCP="" yes or no, default to no
# export DEPLOY_SSH_SCP_CMD="" defaults to "scp -q"
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

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  # USER is required to login by SSH to remote host.
  _migratedeployconf Le_Deploy_ssh_user DEPLOY_SSH_USER
  _getdeployconf DEPLOY_SSH_USER
  _debug2 DEPLOY_SSH_USER "$DEPLOY_SSH_USER"
  if [ -z "$DEPLOY_SSH_USER" ]; then
    _err "DEPLOY_SSH_USER not defined."
    return 1
  fi
  _savedeployconf DEPLOY_SSH_USER "$DEPLOY_SSH_USER"

  # SERVER is optional. If not provided then use _cdomain
  _migratedeployconf Le_Deploy_ssh_server DEPLOY_SSH_SERVER
  _getdeployconf DEPLOY_SSH_SERVER
  _debug2 DEPLOY_SSH_SERVER "$DEPLOY_SSH_SERVER"
  if [ -z "$DEPLOY_SSH_SERVER" ]; then
    DEPLOY_SSH_SERVER="$_cdomain"
  fi
  _savedeployconf DEPLOY_SSH_SERVER "$DEPLOY_SSH_SERVER"

  # CMD is optional. If not provided then use ssh
  _migratedeployconf Le_Deploy_ssh_cmd DEPLOY_SSH_CMD
  _getdeployconf DEPLOY_SSH_CMD
  _debug2 DEPLOY_SSH_CMD "$DEPLOY_SSH_CMD"
  if [ -z "$DEPLOY_SSH_CMD" ]; then
    DEPLOY_SSH_CMD="ssh -T"
  fi
  _savedeployconf DEPLOY_SSH_CMD "$DEPLOY_SSH_CMD"

  # BACKUP is optional. If not provided then default to previously saved value or yes.
  _migratedeployconf Le_Deploy_ssh_backup DEPLOY_SSH_BACKUP
  _getdeployconf DEPLOY_SSH_BACKUP
  _debug2 DEPLOY_SSH_BACKUP "$DEPLOY_SSH_BACKUP"
  if [ -z "$DEPLOY_SSH_BACKUP" ]; then
    DEPLOY_SSH_BACKUP="yes"
  fi
  _savedeployconf DEPLOY_SSH_BACKUP "$DEPLOY_SSH_BACKUP"

  # BACKUP_PATH is optional. If not provided then default to previously saved value or .acme_ssh_deploy
  _migratedeployconf Le_Deploy_ssh_backup_path DEPLOY_SSH_BACKUP_PATH
  _getdeployconf DEPLOY_SSH_BACKUP_PATH
  _debug2 DEPLOY_SSH_BACKUP_PATH "$DEPLOY_SSH_BACKUP_PATH"
  if [ -z "$DEPLOY_SSH_BACKUP_PATH" ]; then
    DEPLOY_SSH_BACKUP_PATH=".acme_ssh_deploy"
  fi
  _savedeployconf DEPLOY_SSH_BACKUP_PATH "$DEPLOY_SSH_BACKUP_PATH"

  # MULTI_CALL is optional. If not provided then default to previously saved
  # value (which may be undefined... equivalent to "no").
  _migratedeployconf Le_Deploy_ssh_multi_call DEPLOY_SSH_MULTI_CALL
  _getdeployconf DEPLOY_SSH_MULTI_CALL
  _debug2 DEPLOY_SSH_MULTI_CALL "$DEPLOY_SSH_MULTI_CALL"
  if [ -z "$DEPLOY_SSH_MULTI_CALL" ]; then
    DEPLOY_SSH_MULTI_CALL="no"
  fi
  _savedeployconf DEPLOY_SSH_MULTI_CALL "$DEPLOY_SSH_MULTI_CALL"

  # KEYFILE is optional.
  # If provided then private key will be copied to provided filename.
  _migratedeployconf Le_Deploy_ssh_keyfile DEPLOY_SSH_KEYFILE
  _getdeployconf DEPLOY_SSH_KEYFILE
  _debug2 DEPLOY_SSH_KEYFILE "$DEPLOY_SSH_KEYFILE"
  if [ -n "$DEPLOY_SSH_KEYFILE" ]; then
    _savedeployconf DEPLOY_SSH_KEYFILE "$DEPLOY_SSH_KEYFILE"
  fi

  # CERTFILE is optional.
  # If provided then certificate will be copied or appended to provided filename.
  _migratedeployconf Le_Deploy_ssh_certfile DEPLOY_SSH_CERTFILE
  _getdeployconf DEPLOY_SSH_CERTFILE
  _debug2 DEPLOY_SSH_CERTFILE "$DEPLOY_SSH_CERTFILE"
  if [ -n "$DEPLOY_SSH_CERTFILE" ]; then
    _savedeployconf DEPLOY_SSH_CERTFILE "$DEPLOY_SSH_CERTFILE"
  fi

  # CAFILE is optional.
  # If provided then CA intermediate certificate will be copied or appended to provided filename.
  _migratedeployconf Le_Deploy_ssh_cafile DEPLOY_SSH_CAFILE
  _getdeployconf DEPLOY_SSH_CAFILE
  _debug2 DEPLOY_SSH_CAFILE "$DEPLOY_SSH_CAFILE"
  if [ -n "$DEPLOY_SSH_CAFILE" ]; then
    _savedeployconf DEPLOY_SSH_CAFILE "$DEPLOY_SSH_CAFILE"
  fi

  # FULLCHAIN is optional.
  # If provided then fullchain certificate will be copied or appended to provided filename.
  _migratedeployconf Le_Deploy_ssh_fullchain DEPLOY_SSH_FULLCHAIN
  _getdeployconf DEPLOY_SSH_FULLCHAIN
  _debug2 DEPLOY_SSH_FULLCHAIN "$DEPLOY_SSH_FULLCHAIN"
  if [ -n "$DEPLOY_SSH_FULLCHAIN" ]; then
    _savedeployconf DEPLOY_SSH_FULLCHAIN "$DEPLOY_SSH_FULLCHAIN"
  fi

  # REMOTE_CMD is optional.
  # If provided then this command will be executed on remote host.
  _migratedeployconf Le_Deploy_ssh_remote_cmd DEPLOY_SSH_REMOTE_CMD
  _getdeployconf DEPLOY_SSH_REMOTE_CMD
  _debug2 DEPLOY_SSH_REMOTE_CMD "$DEPLOY_SSH_REMOTE_CMD"
  if [ -n "$DEPLOY_SSH_REMOTE_CMD" ]; then
    _savedeployconf DEPLOY_SSH_REMOTE_CMD "$DEPLOY_SSH_REMOTE_CMD"
  fi

  # USE_SCP is optional. If not provided then default to previously saved
  # value (which may be undefined... equivalent to "no").
  _getdeployconf DEPLOY_SSH_USE_SCP
  _debug2 DEPLOY_SSH_USE_SCP "$DEPLOY_SSH_USE_SCP"
  if [ -z "$DEPLOY_SSH_USE_SCP" ]; then
    DEPLOY_SSH_USE_SCP="no"
  fi
  _savedeployconf DEPLOY_SSH_USE_SCP "$DEPLOY_SSH_USE_SCP"

  # SCP_CMD is optional. If not provided then use scp
  _getdeployconf DEPLOY_SSH_SCP_CMD
  _debug2 DEPLOY_SSH_SCP_CMD "$DEPLOY_SSH_SCP_CMD"
  if [ -z "$DEPLOY_SSH_SCP_CMD" ]; then
    DEPLOY_SSH_SCP_CMD="scp -q"
  fi
  _savedeployconf DEPLOY_SSH_SCP_CMD "$DEPLOY_SSH_SCP_CMD"

  if [ "$DEPLOY_SSH_USE_SCP" = "yes" ]; then
    DEPLOY_SSH_MULTI_CALL="yes"
    _info "Using scp as alternate method for copying files. Multicall Mode is implicit"
  elif [ "$DEPLOY_SSH_MULTI_CALL" = "yes" ]; then
    _info "Using MULTI_CALL mode... Required commands sent in multiple calls to remote host"
  else
    _info "Required commands batched and sent in single call to remote host"
  fi

  _deploy_ssh_servers="$DEPLOY_SSH_SERVER"
  for DEPLOY_SSH_SERVER in $_deploy_ssh_servers; do
    _ssh_deploy
  done
}

_ssh_deploy() {
  _err_code=0
  _cmdstr=""
  _backupprefix=""
  _backupdir=""
  _local_cert_file=""
  _local_ca_file=""
  _local_full_file=""

  case $DEPLOY_SSH_SERVER in
  *:*)
    _host=${DEPLOY_SSH_SERVER%:*}
    _port=${DEPLOY_SSH_SERVER##*:}
    ;;
  *)
    _host=$DEPLOY_SSH_SERVER
    _port=
    ;;
  esac

  _info "Deploy certificates to remote server $DEPLOY_SSH_USER@$_host:$_port"

  if [ "$DEPLOY_SSH_BACKUP" = "yes" ]; then
    _backupprefix="$DEPLOY_SSH_BACKUP_PATH/$_cdomain-backup"
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
    if [ "$DEPLOY_SSH_MULTI_CALL" = "yes" ]; then
      if ! _ssh_remote_cmd "$_cmdstr"; then
        return $_err_code
      fi
      _cmdstr=""
    fi
  fi

  if [ -n "$DEPLOY_SSH_KEYFILE" ]; then
    if [ "$DEPLOY_SSH_BACKUP" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $DEPLOY_SSH_KEYFILE $_backupdir >/dev/null;"
      if [ "$DEPLOY_SSH_MULTI_CALL" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi

    # copy new key into file.
    if [ "$DEPLOY_SSH_USE_SCP" = "yes" ]; then
      # scp the file
      if ! _scp_remote_cmd "$_ckey" "$DEPLOY_SSH_KEYFILE"; then
        return $_err_code
      fi
    else
      # ssh echo to the file
      _cmdstr="$_cmdstr echo \"$(cat "$_ckey")\" > $DEPLOY_SSH_KEYFILE;"
      _info "will copy private key to remote file $DEPLOY_SSH_KEYFILE"
      if [ "$DEPLOY_SSH_MULTI_CALL" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi
  fi

  if [ -n "$DEPLOY_SSH_CERTFILE" ]; then
    _pipe=">"
    if [ "$DEPLOY_SSH_CERTFILE" = "$DEPLOY_SSH_KEYFILE" ]; then
      # if filename is same as previous file then append.
      _pipe=">>"
    elif [ "$DEPLOY_SSH_BACKUP" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $DEPLOY_SSH_CERTFILE $_backupdir >/dev/null;"
      if [ "$DEPLOY_SSH_MULTI_CALL" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi

    # copy new certificate into file.
    if [ "$DEPLOY_SSH_USE_SCP" = "yes" ]; then
      # scp the file
      _local_cert_file=$(_mktemp)
      if [ "$DEPLOY_SSH_CERTFILE" = "$DEPLOY_SSH_KEYFILE" ]; then
        cat "$_ckey" >>"$_local_cert_file"
      fi
      cat "$_ccert" >>"$_local_cert_file"
      if ! _scp_remote_cmd "$_local_cert_file" "$DEPLOY_SSH_CERTFILE"; then
        return $_err_code
      fi
    else
      # ssh echo to the file
      _cmdstr="$_cmdstr echo \"$(cat "$_ccert")\" $_pipe $DEPLOY_SSH_CERTFILE;"
      _info "will copy certificate to remote file $DEPLOY_SSH_CERTFILE"
      if [ "$DEPLOY_SSH_MULTI_CALL" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi
  fi

  if [ -n "$DEPLOY_SSH_CAFILE" ]; then
    _pipe=">"
    if [ "$DEPLOY_SSH_CAFILE" = "$DEPLOY_SSH_KEYFILE" ] ||
      [ "$DEPLOY_SSH_CAFILE" = "$DEPLOY_SSH_CERTFILE" ]; then
      # if filename is same as previous file then append.
      _pipe=">>"
    elif [ "$DEPLOY_SSH_BACKUP" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $DEPLOY_SSH_CAFILE $_backupdir >/dev/null;"
      if [ "$DEPLOY_SSH_MULTI_CALL" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi

    # copy new certificate into file.
    if [ "$DEPLOY_SSH_USE_SCP" = "yes" ]; then
      # scp the file
      _local_ca_file=$(_mktemp)
      if [ "$DEPLOY_SSH_CAFILE" = "$DEPLOY_SSH_KEYFILE" ]; then
        cat "$_ckey" >>"$_local_ca_file"
      fi
      if [ "$DEPLOY_SSH_CAFILE" = "$DEPLOY_SSH_CERTFILE" ]; then
        cat "$_ccert" >>"$_local_ca_file"
      fi
      cat "$_cca" >>"$_local_ca_file"
      if ! _scp_remote_cmd "$_local_ca_file" "$DEPLOY_SSH_CAFILE"; then
        return $_err_code
      fi
    else
      # ssh echo to the file
      _cmdstr="$_cmdstr echo \"$(cat "$_cca")\" $_pipe $DEPLOY_SSH_CAFILE;"
      _info "will copy CA file to remote file $DEPLOY_SSH_CAFILE"
      if [ "$DEPLOY_SSH_MULTI_CALL" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi
  fi

  if [ -n "$DEPLOY_SSH_FULLCHAIN" ]; then
    _pipe=">"
    if [ "$DEPLOY_SSH_FULLCHAIN" = "$DEPLOY_SSH_KEYFILE" ] ||
      [ "$DEPLOY_SSH_FULLCHAIN" = "$DEPLOY_SSH_CERTFILE" ] ||
      [ "$DEPLOY_SSH_FULLCHAIN" = "$DEPLOY_SSH_CAFILE" ]; then
      # if filename is same as previous file then append.
      _pipe=">>"
    elif [ "$DEPLOY_SSH_BACKUP" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $DEPLOY_SSH_FULLCHAIN $_backupdir >/dev/null;"
      if [ "$DEPLOY_SSH_FULLCHAIN" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi

    # copy new certificate into file.
    if [ "$DEPLOY_SSH_USE_SCP" = "yes" ]; then
      # scp the file
      _local_full_file=$(_mktemp)
      if [ "$DEPLOY_SSH_FULLCHAIN" = "$DEPLOY_SSH_KEYFILE" ]; then
        cat "$_ckey" >>"$_local_full_file"
      fi
      if [ "$DEPLOY_SSH_FULLCHAIN" = "$DEPLOY_SSH_CERTFILE" ]; then
        cat "$_ccert" >>"$_local_full_file"
      fi
      if [ "$DEPLOY_SSH_FULLCHAIN" = "$DEPLOY_SSH_CAFILE" ]; then
        cat "$_cca" >>"$_local_full_file"
      fi
      cat "$_cfullchain" >>"$_local_full_file"
      if ! _scp_remote_cmd "$_local_full_file" "$DEPLOY_SSH_FULLCHAIN"; then
        return $_err_code
      fi
    else
      # ssh echo to the file
      _cmdstr="$_cmdstr echo \"$(cat "$_cfullchain")\" $_pipe $DEPLOY_SSH_FULLCHAIN;"
      _info "will copy fullchain to remote file $DEPLOY_SSH_FULLCHAIN"
      if [ "$DEPLOY_SSH_MULTI_CALL" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi
  fi

  # cleanup local files if any
  if [ -f "$_local_cert_file" ]; then
    rm -f "$_local_cert_file"
  fi
  if [ -f "$_local_ca_file" ]; then
    rm -f "$_local_ca_file"
  fi
  if [ -f "$_local_full_file" ]; then
    rm -f "$_local_full_file"
  fi

  if [ -n "$DEPLOY_SSH_REMOTE_CMD" ]; then
    _cmdstr="$_cmdstr $DEPLOY_SSH_REMOTE_CMD;"
    _info "Will execute remote command $DEPLOY_SSH_REMOTE_CMD"
    if [ "$DEPLOY_SSH_MULTI_CALL" = "yes" ]; then
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
  # cleanup in case all is ok
  return 0
}

#cmd
_ssh_remote_cmd() {
  _cmd="$1"

  _ssh_cmd="$DEPLOY_SSH_CMD"
  if [ -n "$_port" ]; then
    _ssh_cmd="$_ssh_cmd -p $_port"
  fi

  _secure_debug "Remote commands to execute: $_cmd"
  _info "Submitting sequence of commands to remote server by $_ssh_cmd"

  # quotations in bash cmd below intended.  Squash travis spellcheck error
  # shellcheck disable=SC2029
  $_ssh_cmd "$DEPLOY_SSH_USER@$_host" sh -c "'$_cmd'"
  _err_code="$?"

  if [ "$_err_code" != "0" ]; then
    _err "Error code $_err_code returned from ssh"
  fi

  return $_err_code
}

# cmd scp
_scp_remote_cmd() {
  _src=$1
  _dest=$2

  _scp_cmd="$DEPLOY_SSH_SCP_CMD"
  if [ -n "$_port" ]; then
    _scp_cmd="$_scp_cmd -P $_port"
  fi

  _secure_debug "Remote copy source $_src to destination $_dest"
  _info "Submitting secure copy by $_scp_cmd"

  $_scp_cmd "$_src" "$DEPLOY_SSH_USER"@"$_host":"$_dest"
  _err_code="$?"

  if [ "$_err_code" != "0" ]; then
    _err "Error code $_err_code returned from scp"
  fi

  return $_err_code
}
