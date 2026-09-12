#!/usr/bin/env sh

# Script to deploy a certificate to a JetKVM (https://jetkvm.com) KVM-over-IP
# device over SSH.
#
# JetKVM only supports key-based SSH authentication (root@<device>, password
# logins are disabled) once "Developer Mode" is enabled and a public key is
# pasted into its web UI (Settings > Advanced). SSH keys must already be
# exchanged and a passwordless login confirmed working (e.g. `ssh
# root@jetkvm.example.com true`) before using this hook.
#
# JetKVM's minimal userspace does not ship an scp binary or SFTP server, so
# unlike deploy/ssh.sh this hook has no "use scp" option: it always writes
# the certificate and key by piping a small POSIX shell script to the
# remote "sh" over stdin (only depends on "sh", "cat", "chmod", "mkdir" and
# "mv" on the device side).
#
# JetKVM's "Custom" TLS mode (device web UI: Settings > Network > HTTPS
# Mode, must already be set to "Custom" before this hook's uploads take
# effect) reads the certificate/key from a fixed location and does not
# hot-reload: a full device reboot is required to pick up a new
# certificate. This hook defaults its restart command to "reboot" for that
# reason, since it's meant to run unattended from cron-driven renewals
# (typically overnight, when an active KVM-over-IP session is unlikely).
#
# The certificate and key are staged under temporary names on the device
# and only renamed into their final names (an atomic "mv", on the same
# filesystem) once both have been fully written and chmod'ed. This keeps a
# dropped connection or a failed write from ever leaving the device with a
# truncated or mismatched certificate/key pair for its own HTTPS listener.
#
# None of the above (storage path, filenames, reboot-to-apply behavior) is
# part of JetKVM's stable/documented API; it was confirmed against real
# JetKVM hardware, but is worth a spot-check after a JetKVM firmware
# upgrade.
#
# The following variables exported from environment will be used. If not
# set then values previously saved in the domain.conf file are used. All
# of them are optional.
#
# export DEPLOY_JETKVM_USER="root"                        # defaults to "root"
# export DEPLOY_JETKVM_HOST="jetkvm.example.com"          # defaults to the cert's domain
# export DEPLOY_JETKVM_PORT="22"                          # defaults to 22
# export DEPLOY_JETKVM_SSH_CMD="ssh -T"                   # defaults to "ssh -T"
# export DEPLOY_JETKVM_REMOTE_PATH="/userdata/jetkvm/tls" # defaults to JetKVM's confirmed "Custom" TLS storage path
# export DEPLOY_JETKVM_CERT_NAME="user-defined.crt"       # defaults to JetKVM's confirmed "Custom" cert filename
# export DEPLOY_JETKVM_KEY_NAME="user-defined.key"        # defaults to JetKVM's confirmed "Custom" key filename
# export DEPLOY_JETKVM_CHMOD_CERT="0644"                  # defaults to 0644
# export DEPLOY_JETKVM_CHMOD_KEY="0600"                   # defaults to 0600
# export DEPLOY_JETKVM_RESTART_CMD="reboot"               # defaults to "reboot", JetKVM has no hot-reload
#
# Example:
# ```sh
# export DEPLOY_JETKVM_HOST="192.168.1.50"
# acme.sh --deploy -d jetkvm.example.com --deploy-hook jetkvm
# ```
#
# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
jetkvm_deploy() {
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

  _getdeployconf DEPLOY_JETKVM_USER
  if [ -z "$DEPLOY_JETKVM_USER" ]; then
    DEPLOY_JETKVM_USER="root"
  fi
  _savedeployconf DEPLOY_JETKVM_USER "$DEPLOY_JETKVM_USER"

  _getdeployconf DEPLOY_JETKVM_HOST
  if [ -z "$DEPLOY_JETKVM_HOST" ]; then
    _debug "Using _cdomain as DEPLOY_JETKVM_HOST, please set if not correct."
    DEPLOY_JETKVM_HOST="$_cdomain"
  fi
  _savedeployconf DEPLOY_JETKVM_HOST "$DEPLOY_JETKVM_HOST"

  _getdeployconf DEPLOY_JETKVM_PORT
  if [ -z "$DEPLOY_JETKVM_PORT" ]; then
    DEPLOY_JETKVM_PORT="22"
  fi
  _savedeployconf DEPLOY_JETKVM_PORT "$DEPLOY_JETKVM_PORT"

  _getdeployconf DEPLOY_JETKVM_SSH_CMD
  if [ -z "$DEPLOY_JETKVM_SSH_CMD" ]; then
    DEPLOY_JETKVM_SSH_CMD="ssh -T"
  fi
  _savedeployconf DEPLOY_JETKVM_SSH_CMD "$DEPLOY_JETKVM_SSH_CMD"

  _getdeployconf DEPLOY_JETKVM_REMOTE_PATH
  if [ -z "$DEPLOY_JETKVM_REMOTE_PATH" ]; then
    DEPLOY_JETKVM_REMOTE_PATH="/userdata/jetkvm/tls"
  fi
  _savedeployconf DEPLOY_JETKVM_REMOTE_PATH "$DEPLOY_JETKVM_REMOTE_PATH"

  _getdeployconf DEPLOY_JETKVM_CERT_NAME
  if [ -z "$DEPLOY_JETKVM_CERT_NAME" ]; then
    DEPLOY_JETKVM_CERT_NAME="user-defined.crt"
  fi
  _savedeployconf DEPLOY_JETKVM_CERT_NAME "$DEPLOY_JETKVM_CERT_NAME"

  _getdeployconf DEPLOY_JETKVM_KEY_NAME
  if [ -z "$DEPLOY_JETKVM_KEY_NAME" ]; then
    DEPLOY_JETKVM_KEY_NAME="user-defined.key"
  fi
  _savedeployconf DEPLOY_JETKVM_KEY_NAME "$DEPLOY_JETKVM_KEY_NAME"

  _getdeployconf DEPLOY_JETKVM_CHMOD_CERT
  if [ -z "$DEPLOY_JETKVM_CHMOD_CERT" ]; then
    DEPLOY_JETKVM_CHMOD_CERT="0644"
  fi
  _savedeployconf DEPLOY_JETKVM_CHMOD_CERT "$DEPLOY_JETKVM_CHMOD_CERT"

  _getdeployconf DEPLOY_JETKVM_CHMOD_KEY
  if [ -z "$DEPLOY_JETKVM_CHMOD_KEY" ]; then
    DEPLOY_JETKVM_CHMOD_KEY="0600"
  fi
  _savedeployconf DEPLOY_JETKVM_CHMOD_KEY "$DEPLOY_JETKVM_CHMOD_KEY"

  _getdeployconf DEPLOY_JETKVM_RESTART_CMD
  if [ -z "$DEPLOY_JETKVM_RESTART_CMD" ]; then
    DEPLOY_JETKVM_RESTART_CMD="reboot"
  fi
  _savedeployconf DEPLOY_JETKVM_RESTART_CMD "$DEPLOY_JETKVM_RESTART_CMD"

  _info "Deploying certificate to JetKVM device $DEPLOY_JETKVM_USER@$DEPLOY_JETKVM_HOST:$DEPLOY_JETKVM_PORT"

  _jetkvm_remote_path="${DEPLOY_JETKVM_REMOTE_PATH%/}"
  _jetkvm_run_id="$$.$(date +%s 2>/dev/null || echo 0)"
  _jetkvm_cert_marker="ACME_JETKVM_CERT_$_jetkvm_run_id"
  _jetkvm_key_marker="ACME_JETKVM_KEY_$_jetkvm_run_id"
  _jetkvm_cert_tmp="$_jetkvm_remote_path/.$DEPLOY_JETKVM_CERT_NAME.tmp.$_jetkvm_run_id"
  _jetkvm_key_tmp="$_jetkvm_remote_path/.$DEPLOY_JETKVM_KEY_NAME.tmp.$_jetkvm_run_id"
  _jetkvm_cert_target="$_jetkvm_remote_path/$DEPLOY_JETKVM_CERT_NAME"
  _jetkvm_key_target="$_jetkvm_remote_path/$DEPLOY_JETKVM_KEY_NAME"

  # Command substitution strips all trailing newlines, so the printf below
  # always emits the content with exactly one trailing newline before the
  # heredoc terminator -- regardless of whether the source file already
  # ended with one -- so the terminator is guaranteed to start its own line.
  _jetkvm_cert_content="$(cat "$_cfullchain")"
  _jetkvm_key_content="$(cat "$_ckey")"

  _jetkvm_script="$(_mktemp)"
  {
    echo "#!/bin/sh"
    echo "set -e"
    echo "umask 077"
    echo "mkdir -p '$_jetkvm_remote_path'"
    echo "cat > '$_jetkvm_cert_tmp' <<'$_jetkvm_cert_marker'"
    printf '%s\n' "$_jetkvm_cert_content"
    echo "$_jetkvm_cert_marker"
    echo "chmod '$DEPLOY_JETKVM_CHMOD_CERT' '$_jetkvm_cert_tmp'"
    echo "cat > '$_jetkvm_key_tmp' <<'$_jetkvm_key_marker'"
    printf '%s\n' "$_jetkvm_key_content"
    echo "$_jetkvm_key_marker"
    echo "chmod '$DEPLOY_JETKVM_CHMOD_KEY' '$_jetkvm_key_tmp'"
    echo "mv '$_jetkvm_cert_tmp' '$_jetkvm_cert_target'"
    echo "mv '$_jetkvm_key_tmp' '$_jetkvm_key_target'"
    if [ -n "$DEPLOY_JETKVM_RESTART_CMD" ]; then
      echo "$DEPLOY_JETKVM_RESTART_CMD"
    fi
  } >"$_jetkvm_script"

  _secure_debug "Generated remote script" "$(cat "$_jetkvm_script")"

  _info "Uploading certificate and key to $_jetkvm_remote_path on the device"
  # shellcheck disable=SC2086
  $DEPLOY_JETKVM_SSH_CMD -p "$DEPLOY_JETKVM_PORT" "$DEPLOY_JETKVM_USER@$DEPLOY_JETKVM_HOST" sh <"$_jetkvm_script"
  _ret=$?

  rm -f "$_jetkvm_script"

  if [ "$_ret" != "0" ]; then
    _err "Error code $_ret returned deploying certificate to JetKVM device"
  else
    _info "Certificate successfully deployed to JetKVM device"
  fi

  return $_ret
}
