#!/usr/bin/env sh
# Deploy hook for Home Assistant OS (HAOS).
#
# Copies the certificate and key to /ssl/ on the HAOS host via SCP,
# then restarts HA Core to pick up the new cert.
#
# The HAOS Terminal & SSH add-on must be installed and reachable.
# Key-based SSH auth is expected (no interactive password prompt).
#
# Settings:
#   DEPLOY_HAOS_HOST    - HAOS SSH host (required)
#   DEPLOY_HAOS_PORT    - HAOS SSH port (default: "22")
#   DEPLOY_HAOS_USER    - HAOS SSH user (default: "root")
#
# Example:
#   export DEPLOY_HAOS_HOST="192.168.1.10"
#   acme.sh --deploy -d example.com --deploy-hook haos

haos_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _getdeployconf DEPLOY_HAOS_HOST
  _getdeployconf DEPLOY_HAOS_PORT
  _getdeployconf DEPLOY_HAOS_USER

  if [ -z "$DEPLOY_HAOS_HOST" ]; then
    _err "DEPLOY_HAOS_HOST must be set."
    return 1
  fi
  DEPLOY_HAOS_PORT="${DEPLOY_HAOS_PORT:-22}"
  DEPLOY_HAOS_USER="${DEPLOY_HAOS_USER:-root}"

  _ssh_base="-o StrictHostKeyChecking=accept-new"
  _ssh_opts="$_ssh_base -p $DEPLOY_HAOS_PORT"
  _scp_opts="$_ssh_base -P $DEPLOY_HAOS_PORT"

  _info "Deploying certificate to HAOS at $DEPLOY_HAOS_HOST..."

  # shellcheck disable=SC2086
  if ! scp -q $_scp_opts "$_cfullchain" "$DEPLOY_HAOS_USER@$DEPLOY_HAOS_HOST:/ssl/fullchain.cer"; then
    _err "Failed to copy fullchain to HAOS."
    return 1
  fi

  # shellcheck disable=SC2086
  if ! scp -q $_scp_opts "$_ckey" "$DEPLOY_HAOS_USER@$DEPLOY_HAOS_HOST:/ssl/key.key"; then
    _err "Failed to copy key to HAOS."
    return 1
  fi

  _info "Restarting Home Assistant Core..."
  # shellcheck disable=SC2086
  if ! ssh -q $_ssh_opts "$DEPLOY_HAOS_USER@$DEPLOY_HAOS_HOST" "ha core restart" >/dev/null 2>&1; then
    _err "Certificate files deployed but HA Core restart failed."
    return 1
  fi

  _savedeployconf DEPLOY_HAOS_HOST "$DEPLOY_HAOS_HOST"
  _savedeployconf DEPLOY_HAOS_PORT "$DEPLOY_HAOS_PORT"
  _savedeployconf DEPLOY_HAOS_USER "$DEPLOY_HAOS_USER"

  _info "Home Assistant certificate deployed and service restarted successfully."
  return 0
}
