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
# Optional Config Sets
# To run multiple ssh deployments with different configrations, define suffixes for each run:
# export DEPLOY_SSH_CONFIG_SETS="_QNAP _UNIFI"
#
# Then define the configuration for each set by suffixing the above configuration values, e.g.:
# export DEPLOY_SSH_USER_QNAP="admin"  # required
# export DEPLOY_SSH_SERVER_QNAP="192.168.0.1:9022"  # defaults to domain name, support multiple servers with optional port
# ...
# export DEPLOY_SSH_REMOTE_CMD="/etc/init.d/stunnel.sh restart"
#
# export DEPLOY_SSH_USER_UNIFI="administrator"  # required
# export DEPLOY_SSH_SERVER_UNIFI="192.168.0.2"  # defaults to domain name, support multiple servers with optional port
# ...
# export DEPLOY_SSH_REMOTE_UNIFI="service unifi restart"
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

  _migratedeployconf Le_Deploy_ssh_user DEPLOY_SSH_USER
  _getdeployconf DEPLOY_SSH_USER
  _getdeployconf DEPLOY_SSH_CONFIG_SETS

  if [ -z "$DEPLOY_SSH_USER" ] && [ -z "$DEPLOY_SSH_CONFIG_SETS" ]; then
    _err "DEPLOY_SSH_USER or DEPLOY_SSH_CONFIG_SETS must be defined."
    return 1
  fi

  if [ -n "$DEPLOY_SSH_USER" ]; then
    _info "Running with base env (no config suffixes)"
    if ! _ssh_load_config; then
      return 1
    fi

    _deploy_ssh_servers="$_sshServer"
    for _sshServer in $_deploy_ssh_servers; do
      _ssh_deploy
    done
  fi

  if [ -n "$DEPLOY_SSH_CONFIG_SETS" ]; then
    _debug2 DEPLOY_SSH_CONFIG_SETS "$DEPLOY_SSH_CONFIG_SETS"
    _savedeployconf DEPLOY_SSH_CONFIG_SETS "$DEPLOY_SSH_CONFIG_SETS"

    for _config_suffix in $DEPLOY_SSH_CONFIG_SETS; do
      _info "Running with config suffix $_config_suffix"
      if ! _ssh_load_config "$_config_suffix"; then
        return 1
      fi

      _deploy_ssh_servers="$_sshServer"
      for _sshServer in $_deploy_ssh_servers; do
        _ssh_deploy
      done
    done
  fi
}

_ssh_load_config() {
  _config_suffix="$1"
  _deploy_ssh_servers=""

  # USER is required to login by SSH to remote host.
  _migratedeployconf Le_Deploy_ssh_user"${_config_suffix}" DEPLOY_SSH_USER"${_config_suffix}"
  _getdeployconf DEPLOY_SSH_USER"${_config_suffix}"
  _sshUser=$(eval echo \$DEPLOY_SSH_USER"${_config_suffix}")
  _debug2 DEPLOY_SSH_USER"${_config_suffix}" "$_sshUser"
  if [ -z "$_sshUser" ]; then
    _err "DEPLOY_SSH_USER${_config_suffix} not defined."
    return 1
  fi
  _savedeployconf DEPLOY_SSH_USER"${_config_suffix}" "$_sshUser"

  # SERVER is optional. If not provided then use _cdomain
  _migratedeployconf Le_Deploy_ssh_server"${_config_suffix}" DEPLOY_SSH_SERVER"${_config_suffix}"
  _getdeployconf DEPLOY_SSH_SERVER"${_config_suffix}"
  _sshServer=$(eval echo \$DEPLOY_SSH_SERVER"${_config_suffix}")
  _debug2 DEPLOY_SSH_SERVER"${_config_suffix}" "$_sshServer"
  if [ -z "$_sshServer" ]; then
    _sshServer="$_cdomain"
  fi
  _savedeployconf DEPLOY_SSH_SERVER"${_config_suffix}" "$_sshServer"

  # CMD is optional. If not provided then use ssh
  _migratedeployconf Le_Deploy_ssh_cmd"${_config_suffix}" DEPLOY_SSH_CMD"${_config_suffix}"
  _getdeployconf DEPLOY_SSH_CMD"${_config_suffix}"
  _sshCmd=$(eval echo \$DEPLOY_SSH_CMD"${_config_suffix}")
  _debug2 DEPLOY_SSH_CMD"${_config_suffix}" "$_sshCmd"
  if [ -z "$_sshCmd" ]; then
    _sshCmd="ssh -T"
  fi
  _savedeployconf DEPLOY_SSH_CMD"${_config_suffix}" "$_sshCmd"

  # BACKUP is optional. If not provided then default to previously saved value or yes.
  _migratedeployconf Le_Deploy_ssh_backup"${_config_suffix}" DEPLOY_SSH_BACKUP"${_config_suffix}"
  _getdeployconf DEPLOY_SSH_BACKUP"${_config_suffix}"
  _sshBackup=$(eval echo \$DEPLOY_SSH_BACKUP"${_config_suffix}")
  _debug2 DEPLOY_SSH_BACKUP"${_config_suffix}" "$_sshBackup"
  if [ -z "$_sshBackup" ]; then
    _sshBackup="yes"
  fi
  _savedeployconf DEPLOY_SSH_BACKUP"${_config_suffix}" "$_sshBackup"

  # BACKUP_PATH is optional. If not provided then default to previously saved value or .acme_ssh_deploy
  _migratedeployconf Le_Deploy_ssh_backup_path"${_config_suffix}" DEPLOY_SSH_BACKUP_PATH"${_config_suffix}"
  _getdeployconf DEPLOY_SSH_BACKUP_PATH"${_config_suffix}"
  _sshBackupPath=$(eval echo \$DEPLOY_SSH_BACKUP_PATH"${_config_suffix}")
  _debug2 DEPLOY_SSH_BACKUP_PATH"${_config_suffix}" "$_sshBackupPath"
  if [ -z "$_sshBackupPath" ]; then
    _sshBackupPath=".acme_ssh_deploy"
  fi
  _savedeployconf DEPLOY_SSH_BACKUP_PATH"${_config_suffix}" "$_sshBackupPath"

  # MULTI_CALL is optional. If not provided then default to previously saved
  # value (which may be undefined... equivalent to "no").
  _migratedeployconf Le_Deploy_ssh_multi_call"${_config_suffix}" DEPLOY_SSH_MULTI_CALL"${_config_suffix}"
  _getdeployconf DEPLOY_SSH_MULTI_CALL"${_config_suffix}"
  _multiCall=$(eval echo \$DEPLOY_SSH_MULTI_CALL"${_config_suffix}")
  _debug2 DEPLOY_SSH_MULTI_CALL"${_config_suffix}" "$_multiCall"
  if [ -z "$_multiCall" ]; then
    _multiCall="no"
  fi
  _savedeployconf DEPLOY_SSH_MULTI_CALL"${_config_suffix}" "$_multiCall"

  # KEYFILE is optional.
  # If provided then private key will be copied to provided filename.
  _migratedeployconf Le_Deploy_ssh_keyfile"${_config_suffix}" DEPLOY_SSH_KEYFILE"${_config_suffix}"
  _getdeployconf DEPLOY_SSH_KEYFILE"${_config_suffix}"
  _keyFile=$(eval echo \$DEPLOY_SSH_KEYFILE"${_config_suffix}")
  _debug2 DEPLOY_SSH_KEYFILE"${_config_suffix}" "$_keyFile"
  if [ -n "$_keyFile" ]; then
    _savedeployconf DEPLOY_SSH_KEYFILE"${_config_suffix}" "$_keyFile"
  fi

  # CERTFILE is optional.
  # If provided then certificate will be copied or appended to provided filename.
  _migratedeployconf Le_Deploy_ssh_certfile"${_config_suffix}" DEPLOY_SSH_CERTFILE"${_config_suffix}"
  _getdeployconf DEPLOY_SSH_CERTFILE"${_config_suffix}"
  _certFile=$(eval echo \$DEPLOY_SSH_CERTFILE"${_config_suffix}")
  _debug2 DEPLOY_SSH_CERTFILE"${_config_suffix}" "$_certFile"
  if [ -n "$_certFile" ]; then
    _savedeployconf DEPLOY_SSH_CERTFILE"${_config_suffix}" "$_certFile"
  fi

  # CAFILE is optional.
  # If provided then CA intermediate certificate will be copied or appended to provided filename.
  _migratedeployconf Le_Deploy_ssh_cafile"${_config_suffix}" DEPLOY_SSH_CAFILE"${_config_suffix}"
  _getdeployconf DEPLOY_SSH_CAFILE"${_config_suffix}"
  _caFile=$(eval echo \$DEPLOY_SSH_CAFILE"${_config_suffix}")
  _debug2 DEPLOY_SSH_CAFILE"${_config_suffix}" "$_caFile"
  if [ -n "$_caFile" ]; then
    _savedeployconf DEPLOY_SSH_CAFILE"${_config_suffix}" "$_caFile"
  fi

  # FULLCHAIN is optional.
  # If provided then fullchain certificate will be copied or appended to provided filename.
  _migratedeployconf Le_Deploy_ssh_fullchain"${_config_suffix}" DEPLOY_SSH_FULLCHAIN"${_config_suffix}"
  _getdeployconf DEPLOY_SSH_FULLCHAIN"${_config_suffix}"
  _fullChain=$(eval echo \$DEPLOY_SSH_FULLCHAIN"${_config_suffix}")
  _debug2 DEPLOY_SSH_FULLCHAIN"${_config_suffix}" "$_fullChain"
  if [ -n "$_fullChain" ]; then
    _savedeployconf DEPLOY_SSH_FULLCHAIN"${_config_suffix}" "$_fullChain"
  fi

  # REMOTE_CMD is optional.
  # If provided then this command will be executed on remote host.
  _migratedeployconf Le_Deploy_ssh_remote_cmd"${_config_suffix}" DEPLOY_SSH_REMOTE_CMD"${_config_suffix}"
  _getdeployconf DEPLOY_SSH_REMOTE_CMD"${_config_suffix}"
  _remoteCmd=$(eval echo \$DEPLOY_SSH_REMOTE_CMD"${_config_suffix}")
  _debug2 DEPLOY_SSH_REMOTE_CMD"${_config_suffix}" "$_remoteCmd"
  if [ -n "$_remoteCmd" ]; then
    _savedeployconf DEPLOY_SSH_REMOTE_CMD"${_config_suffix}" "$_remoteCmd"
  fi

  # USE_SCP is optional. If not provided then default to previously saved
  # value (which may be undefined... equivalent to "no").
  _getdeployconf DEPLOY_SSH_USE_SCP"${_config_suffix}"
  _useScp=$(eval echo \$DEPLOY_SSH_USE_SCP"${_config_suffix}")
  _debug2 DEPLOY_SSH_USE_SCP"${_config_suffix}" "$_useScp"
  if [ -z "$_useScp" ]; then
    _useScp="no"
  fi
  _savedeployconf DEPLOY_SSH_USE_SCP"${_config_suffix}" "$_useScp"

  # SCP_CMD is optional. If not provided then use scp
  _getdeployconf DEPLOY_SSH_SCP_CMD"${_config_suffix}"
  _scpCmd=$(eval echo \$DEPLOY_SSH_SCP_CMD"${_config_suffix}")
  _debug2 DEPLOY_SSH_SCP_CMD"${_config_suffix}" "$_scpCmd"
  if [ -z "$_scpCmd" ]; then
    _scpCmd="scp -q"
  fi
  _savedeployconf DEPLOY_SSH_SCP_CMD"${_config_suffix}" "$_scpCmd"

  if [ "$_useScp" = "yes" ]; then
    _multiCall="yes"
    _info "Using scp as alternate method for copying files. Multicall Mode is implicit"
  elif [ "$_multiCall" = "yes" ]; then
    _info "Using MULTI_CALL mode... Required commands sent in multiple calls to remote host"
  else
    _info "Required commands batched and sent in single call to remote host"
  fi
}

_ssh_deploy() {
  _err_code=0
  _cmdstr=""
  _backupprefix=""
  _backupdir=""
  _local_cert_file=""
  _local_ca_file=""
  _local_full_file=""

  case $_sshServer in
  *:*)
    _host=${_sshServer%:*}
    _port=${_sshServer##*:}
    ;;
  *)
    _host=$_sshServer
    _port=
    ;;
  esac

  _info "Deploy certificates to remote server $_sshUser@$_host:$_port"

  if [ "$_sshBackup" = "yes" ]; then
    _backupprefix="$_sshBackupPath/$_cdomain-backup"
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
    if [ "$_multiCall" = "yes" ]; then
      if ! _ssh_remote_cmd "$_cmdstr"; then
        return $_err_code
      fi
      _cmdstr=""
    fi
  fi

  if [ -n "$_keyFile" ]; then
    if [ "$_sshBackup" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $_keyFile $_backupdir >/dev/null;"
      if [ "$_multiCall" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi

    # copy new key into file.
    if [ "$_useScp" = "yes" ]; then
      # scp the file
      if ! _scp_remote_cmd "$_ckey" "$_keyFile"; then
        return $_err_code
      fi
    else
      # ssh echo to the file
      _cmdstr="$_cmdstr echo \"$(cat "$_ckey")\" > $_keyFile;"
      _info "will copy private key to remote file $_keyFile"
      if [ "$_multiCall" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi
  fi

  if [ -n "$_certFile" ]; then
    _pipe=">"
    if [ "$_certFile" = "$_keyFile" ]; then
      # if filename is same as previous file then append.
      _pipe=">>"
    elif [ "$_sshBackup" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $_certFile $_backupdir >/dev/null;"
      if [ "$_multiCall" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi

    # copy new certificate into file.
    if [ "$_useScp" = "yes" ]; then
      # scp the file
      _local_cert_file=$(_mktemp)
      if [ "$_certFile" = "$_keyFile" ]; then
        cat "$_ckey" >>"$_local_cert_file"
      fi
      cat "$_ccert" >>"$_local_cert_file"
      if ! _scp_remote_cmd "$_local_cert_file" "$_certFile"; then
        return $_err_code
      fi
    else
      # ssh echo to the file
      _cmdstr="$_cmdstr echo \"$(cat "$_ccert")\" $_pipe $_certFile;"
      _info "will copy certificate to remote file $_certFile"
      if [ "$_multiCall" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi
  fi

  if [ -n "$_caFile" ]; then
    _pipe=">"
    if [ "$_caFile" = "$_keyFile" ] ||
      [ "$_caFile" = "$_certFile" ]; then
      # if filename is same as previous file then append.
      _pipe=">>"
    elif [ "$_sshBackup" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $_caFile $_backupdir >/dev/null;"
      if [ "$_multiCall" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi

    # copy new certificate into file.
    if [ "$_useScp" = "yes" ]; then
      # scp the file
      _local_ca_file=$(_mktemp)
      if [ "$_caFile" = "$_keyFile" ]; then
        cat "$_ckey" >>"$_local_ca_file"
      fi
      if [ "$_caFile" = "$_certFile" ]; then
        cat "$_ccert" >>"$_local_ca_file"
      fi
      cat "$_cca" >>"$_local_ca_file"
      if ! _scp_remote_cmd "$_local_ca_file" "$_caFile"; then
        return $_err_code
      fi
    else
      # ssh echo to the file
      _cmdstr="$_cmdstr echo \"$(cat "$_cca")\" $_pipe $_caFile;"
      _info "will copy CA file to remote file $_caFile"
      if [ "$_multiCall" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi
  fi

  if [ -n "$_fullChain" ]; then
    _pipe=">"
    if [ "$_fullChain" = "$_keyFile" ] ||
      [ "$_fullChain" = "$_certFile" ] ||
      [ "$_fullChain" = "$_caFile" ]; then
      # if filename is same as previous file then append.
      _pipe=">>"
    elif [ "$_sshBackup" = "yes" ]; then
      # backup file we are about to overwrite.
      _cmdstr="$_cmdstr cp $_fullChain $_backupdir >/dev/null;"
      if [ "$_fullChain" = "yes" ]; then
        if ! _ssh_remote_cmd "$_cmdstr"; then
          return $_err_code
        fi
        _cmdstr=""
      fi
    fi

    # copy new certificate into file.
    if [ "$_useScp" = "yes" ]; then
      # scp the file
      _local_full_file=$(_mktemp)
      if [ "$_fullChain" = "$_keyFile" ]; then
        cat "$_ckey" >>"$_local_full_file"
      fi
      if [ "$_fullChain" = "$_certFile" ]; then
        cat "$_ccert" >>"$_local_full_file"
      fi
      if [ "$_fullChain" = "$_caFile" ]; then
        cat "$_cca" >>"$_local_full_file"
      fi
      cat "$_cfullchain" >>"$_local_full_file"
      if ! _scp_remote_cmd "$_local_full_file" "$_fullChain"; then
        return $_err_code
      fi
    else
      # ssh echo to the file
      _cmdstr="$_cmdstr echo \"$(cat "$_cfullchain")\" $_pipe $_fullChain;"
      _info "will copy fullchain to remote file $_fullChain"
      if [ "$_multiCall" = "yes" ]; then
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

  if [ -n "$_remoteCmd" ]; then
    _cmdstr="$_cmdstr $_remoteCmd;"
    _info "Will execute remote command $_remoteCmd"
    if [ "$_multiCall" = "yes" ]; then
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

  _ssh_cmd="$_sshCmd"
  if [ -n "$_port" ]; then
    _ssh_cmd="$_ssh_cmd -p $_port"
  fi

  _secure_debug "Remote commands to execute: $_cmd"
  _info "Submitting sequence of commands to remote server by $_ssh_cmd"

  # quotations in bash cmd below intended.  Squash travis spellcheck error
  # shellcheck disable=SC2029
  $_ssh_cmd "$_sshUser@$_host" sh -c "'$_cmd'"
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

  _scp_cmd="$_scpCmd"
  if [ -n "$_port" ]; then
    _scp_cmd="$_scp_cmd -P $_port"
  fi

  _secure_debug "Remote copy source $_src to destination $_dest"
  _info "Submitting secure copy by $_scp_cmd"

  $_scp_cmd "$_src" "$_sshUser"@"$_host":"$_dest"
  _err_code="$?"

  if [ "$_err_code" != "0" ]; then
    _err "Error code $_err_code returned from scp"
  fi

  return $_err_code
}
