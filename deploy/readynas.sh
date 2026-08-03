#!/usr/bin/env sh
# Deploy hook for Netgear ReadyNAS (OS 6).
#
# Combines the fullchain and key into the frontview Apache cert file
# and restarts apache2 to pick up the new cert.
#
# Key-based SSH auth to root is expected.
#
# Settings:
#   DEPLOY_READYNAS_HOST    - ReadyNAS SSH host (required)
#   DEPLOY_READYNAS_PORT    - ReadyNAS SSH port (default: "22")
#
# Example:
#   export DEPLOY_READYNAS_HOST="192.168.1.20"
#   acme.sh --deploy -d example.com --deploy-hook readynas

readynas_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _getdeployconf DEPLOY_READYNAS_HOST
  _getdeployconf DEPLOY_READYNAS_PORT

  if [ -z "$DEPLOY_READYNAS_HOST" ]; then
    _err "DEPLOY_READYNAS_HOST must be set."
    return 1
  fi
  DEPLOY_READYNAS_PORT="${DEPLOY_READYNAS_PORT:-22}"

  _ssh_base="-o StrictHostKeyChecking=accept-new"
  _ssh_opts="$_ssh_base -p $DEPLOY_READYNAS_PORT"
  _ssh_target="root@$DEPLOY_READYNAS_HOST"

  _info "Deploying certificate to ReadyNAS at $DEPLOY_READYNAS_HOST..."

  # shellcheck disable=SC2086
  if ! cat "$_cfullchain" "$_ckey" | ssh -q $_ssh_opts "$_ssh_target" 'cat > /etc/frontview/apache/apache2.pem && service apache2 restart'; then
    _err "Failed to deploy certificate to ReadyNAS."
    return 1
  fi

  _savedeployconf DEPLOY_READYNAS_HOST "$DEPLOY_READYNAS_HOST"
  _savedeployconf DEPLOY_READYNAS_PORT "$DEPLOY_READYNAS_PORT"

  _info "ReadyNAS certificate deployed and apache2 restarted successfully."
  return 0
}
