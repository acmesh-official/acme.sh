#!/usr/bin/env sh

# Script to deploy a certificate to a JetKVM (https://jetkvm.com) KVM-over-IP
# device over SSH. See also:
# https://github.com/acmesh-official/acme.sh/wiki/deployhooks
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
# remote "sh" over stdin (only depends on "sh", "cat", "chmod", "mkdir",
# "mv" and "rm" on the device side). The remote path, filenames and file
# permissions are firmware constants on this single-purpose, single-root
# appliance, so they are not configurable here.
#
# JetKVM's "Custom" TLS mode (device web UI: Settings > Network > HTTPS
# Mode, must already be set to "Custom" before this hook's uploads take
# effect) reads the certificate/key from that fixed location and does not
# hot-reload: a device reboot is required to pick up a new certificate.
# This hook's restart command therefore defaults to "reboot" -- a blank
# DEPLOY_JETKVM_RESTART_CMD is treated the same as unset (falls back to
# "reboot") rather than silently skipping it, since a renewed certificate
# that's never actually applied defeats the point of automating this; set
# it to the literal value "none" to opt out and apply/verify manually.
# The restart command is run detached on the device (nohup ... &) so this
# hook's ssh call can return before the reboot itself lands, rather than
# racing the connection teardown.
#
# The certificate and key are staged under fixed temporary names on the
# device and only renamed into their final names (an atomic "mv", on the
# same filesystem) once both have been fully written and chmod'ed. This
# keeps a dropped connection or a failed write from ever leaving the
# device with a truncated or mismatched certificate/key pair for its own
# HTTPS listener, and a "trap ... EXIT" in the generated script removes
# any leftover staged file however that script exits.
#
# Before writing anything, this hook also checks that the device's HTTPS
# Mode is already "Custom" -- uploading a certificate that mode won't
# even serve would otherwise be a silent no-op. There is currently no
# documented/headless way to read this back (JetKVM's own JSON-RPC
# getTLSState/setTLSState calls require an authenticated WebRTC session,
# see https://github.com/jetkvm/kvm/issues/1240 and the still-open
# https://github.com/jetkvm/kvm/pull/1515), so this greps the device's
# own config file instead: JetKVM's firmware (see web_tls.go / config.go
# in https://github.com/jetkvm/kvm) persists the mode as the plain-JSON
# field "tls_mode" (values "", "self-signed", or "custom") in
# /userdata/kvm_config.json.
#
# None of the above (storage path, filenames, config file, reboot-to-apply
# behavior) is part of JetKVM's stable/documented API; it was confirmed
# against real JetKVM hardware, but is worth a spot-check after a JetKVM
# firmware upgrade -- set DEPLOY_JETKVM_REQUIRE_CUSTOM_MODE=no to skip the
# HTTPS-mode check entirely if a future firmware version changes that
# file's format out from under it.
#
# The following variables exported from environment will be used. If not
# set then values previously saved in the domain.conf file are used. All
# of them are optional.
#
# export DEPLOY_JETKVM_USER="root"                        # defaults to "root"
# export DEPLOY_JETKVM_HOST="jetkvm.example.com"          # defaults to the cert's domain
# export DEPLOY_JETKVM_PORT="22"                          # defaults to 22
# export DEPLOY_JETKVM_SSH_CMD="ssh -T"                   # defaults to "ssh -T"
# export DEPLOY_JETKVM_RESTART_CMD="reboot"               # defaults to "reboot"; set to "none" to skip it
# export DEPLOY_JETKVM_REQUIRE_CUSTOM_MODE="yes"          # defaults to "yes" (verify tls_mode=custom before upload); set to "no" to skip
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

  if [ ! -s "$_ckey" ] || [ ! -s "$_cfullchain" ]; then
    _err "JetKVM deploy needs both a private key and a fullchain certificate (not available, e.g., after --signcsr)."
    return 1
  fi

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
  _savedeployconf DEPLOY_JETKVM_SSH_CMD "$DEPLOY_JETKVM_SSH_CMD" "base64"

  _getdeployconf DEPLOY_JETKVM_RESTART_CMD
  if [ -z "$DEPLOY_JETKVM_RESTART_CMD" ]; then
    DEPLOY_JETKVM_RESTART_CMD="reboot"
  fi
  _savedeployconf DEPLOY_JETKVM_RESTART_CMD "$DEPLOY_JETKVM_RESTART_CMD" "base64"

  _getdeployconf DEPLOY_JETKVM_REQUIRE_CUSTOM_MODE
  if [ -z "$DEPLOY_JETKVM_REQUIRE_CUSTOM_MODE" ]; then
    DEPLOY_JETKVM_REQUIRE_CUSTOM_MODE="yes"
  fi
  _savedeployconf DEPLOY_JETKVM_REQUIRE_CUSTOM_MODE "$DEPLOY_JETKVM_REQUIRE_CUSTOM_MODE"

  _info "Deploying certificate to JetKVM device $DEPLOY_JETKVM_USER@$DEPLOY_JETKVM_HOST:$DEPLOY_JETKVM_PORT"

  # Firmware constants on a single-purpose, single-root appliance -- not
  # user configuration. If JetKVM ever moves these, that's a hook update,
  # not a setting (a saved-per-domain override would just as easily hide
  # the fix from anyone already using this hook).
  _jetkvm_remote_path="/userdata/jetkvm/tls"
  _jetkvm_cert_name="user-defined.crt"
  _jetkvm_key_name="user-defined.key"
  _jetkvm_config_file="/userdata/kvm_config.json"
  _jetkvm_mode_exitcode=3
  _jetkvm_config_missing_exitcode=4

  _jetkvm_run_id="$$.$(_time)"
  _jetkvm_cert_marker="ACME_JETKVM_CERT_$_jetkvm_run_id"
  _jetkvm_key_marker="ACME_JETKVM_KEY_$_jetkvm_run_id"
  _jetkvm_cert_tmp="$_jetkvm_remote_path/.$_jetkvm_cert_name.tmp"
  _jetkvm_key_tmp="$_jetkvm_remote_path/.$_jetkvm_key_name.tmp"
  _jetkvm_cert_target="$_jetkvm_remote_path/$_jetkvm_cert_name"
  _jetkvm_key_target="$_jetkvm_remote_path/$_jetkvm_key_name"

  # Command substitution strips all trailing newlines, so the printf below
  # always emits the content with exactly one trailing newline before the
  # heredoc terminator -- regardless of whether the source file already
  # ended with one -- so the terminator is guaranteed to start its own line.
  _jetkvm_cert_content="$(cat "$_cfullchain")"
  _jetkvm_key_content="$(cat "$_ckey")"

  _jetkvm_upload_script="$(
    echo "#!/bin/sh"
    echo "set -e"
    echo "umask 077"
    printf "trap \"rm -f '%s' '%s'\" EXIT\n" "$_jetkvm_cert_tmp" "$_jetkvm_key_tmp"
    if [ "$DEPLOY_JETKVM_REQUIRE_CUSTOM_MODE" != "no" ]; then
      # Uploading a certificate that HTTPS Mode won't even serve would
      # otherwise fail silently -- see the header comment for why this
      # greps the device's own config file rather than querying it
      # through a documented API (there isn't one for reading this
      # headlessly yet). The config file is checked for readability
      # separately so a missing/renamed file isn't misreported as
      # HTTPS Mode being wrong.
      printf "if [ ! -r '%s' ]; then exit %s; fi\n" "$_jetkvm_config_file" "$_jetkvm_config_missing_exitcode"
      printf 'if ! grep -q '\''"tls_mode" *: *"custom"'\'' '\''%s'\''; then exit %s; fi\n' "$_jetkvm_config_file" "$_jetkvm_mode_exitcode"
    fi
    printf "mkdir -p '%s'\n" "$_jetkvm_remote_path"
    printf "cat > '%s' <<'%s'\n" "$_jetkvm_cert_tmp" "$_jetkvm_cert_marker"
    printf '%s\n' "$_jetkvm_cert_content"
    echo "$_jetkvm_cert_marker"
    printf "chmod 0644 '%s'\n" "$_jetkvm_cert_tmp"
    printf "cat > '%s' <<'%s'\n" "$_jetkvm_key_tmp" "$_jetkvm_key_marker"
    printf '%s\n' "$_jetkvm_key_content"
    echo "$_jetkvm_key_marker"
    printf "chmod 0600 '%s'\n" "$_jetkvm_key_tmp"
    printf "mv '%s' '%s'\n" "$_jetkvm_cert_tmp" "$_jetkvm_cert_target"
    printf "mv '%s' '%s'\n" "$_jetkvm_key_tmp" "$_jetkvm_key_target"
  )"

  _secure_debug "Generated upload script" "$_jetkvm_upload_script"

  _info "Connecting to JetKVM device $DEPLOY_JETKVM_USER@$DEPLOY_JETKVM_HOST:$DEPLOY_JETKVM_PORT to deploy certificate"
  # shellcheck disable=SC2086
  printf '%s\n' "$_jetkvm_upload_script" | $DEPLOY_JETKVM_SSH_CMD -p "$DEPLOY_JETKVM_PORT" "$DEPLOY_JETKVM_USER@$DEPLOY_JETKVM_HOST" sh
  _ret=$?

  if [ "$_ret" = "$_jetkvm_config_missing_exitcode" ]; then
    _err "JetKVM config file ($_jetkvm_config_file) was not found or not readable on the device -- this hook's assumptions may be out of date after a firmware upgrade. Certificate was NOT uploaded."
    return "$_ret"
  fi

  if [ "$_ret" = "$_jetkvm_mode_exitcode" ]; then
    _err "JetKVM HTTPS Mode is not set to \"Custom\" (checked \"tls_mode\" in $_jetkvm_config_file on the device). Set it in the device's web UI (Settings > Network > HTTPS Mode) before this hook can take effect. Certificate was NOT uploaded."
    return "$_ret"
  fi

  if [ "$_ret" != "0" ]; then
    _err "Error code $_ret returned uploading certificate to JetKVM device"
    return "$_ret"
  fi

  _info "Certificate and key uploaded to $_jetkvm_remote_path on the device"

  if [ "$DEPLOY_JETKVM_RESTART_CMD" = "none" ]; then
    _info "Certificate successfully deployed to JetKVM device. DEPLOY_JETKVM_RESTART_CMD=none, skipping restart command."
    return 0
  fi

  # Run the restart command detached (nohup ... &) so this ssh call
  # returns as soon as it's launched, before the device actually reboots,
  # rather than racing the connection teardown -- observed, against real
  # hardware, that a reboot racing the SSH session's own exit can make
  # ssh itself exit anywhere from a clean 0 to a connection-reset 255.
  # The tradeoff: a genuinely failing restart command (typo, permission
  # denied) can no longer be detected either, since it now runs after
  # this ssh call has already returned; only a failure to launch it at
  # all is caught below. "sleep" here runs on the device's own shell, not
  # acme.sh's, so acme.sh's _sleep wrapper does not apply.
  _info "Running post-upload command on JetKVM device: $DEPLOY_JETKVM_RESTART_CMD"
  _jetkvm_detached_cmd="nohup sh -c 'sleep 2; $DEPLOY_JETKVM_RESTART_CMD' >/dev/null 2>&1 &"
  # shellcheck disable=SC2086
  if ! $DEPLOY_JETKVM_SSH_CMD -p "$DEPLOY_JETKVM_PORT" "$DEPLOY_JETKVM_USER@$DEPLOY_JETKVM_HOST" "$_jetkvm_detached_cmd"; then
    _err "Certificate was uploaded, but launching the restart command on the JetKVM device failed."
    return 1
  fi

  _info "Certificate deployed to JetKVM device; it will restart shortly to apply it."
  return 0
}
