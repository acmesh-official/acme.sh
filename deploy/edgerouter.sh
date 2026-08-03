#!/usr/bin/env sh
# Deploy hook for Ubiquiti EdgeRouter (EdgeOS).
#
# Deploys the certificate to /config/ssl/ (firmware-upgrade-persistent)
# via SSH, using sudo tee since /config/ssl/ is root-owned.
# Restarts lighttpd to pick up the new cert.
#
# One-time EdgeRouter setup (before first deploy):
#   sudo mkdir -p /config/ssl && sudo chmod 700 /config/ssl
#   configure
#   set service gui cert-file /config/ssl/server.pem
#   set service gui ca-file /config/ssl/ca.cer
#   commit; save
#
# Key-based SSH auth is expected (no interactive password prompt).
# The SSH user must have passwordless sudo (standard for EdgeOS admin).
#
# Settings:
#   DEPLOY_EDGEROUTER_HOST    - EdgeRouter SSH host (default: "192.168.0.1")
#   DEPLOY_EDGEROUTER_PORT    - EdgeRouter SSH port (default: "22")
#   DEPLOY_EDGEROUTER_USER    - EdgeRouter SSH user (required)
#
# Example:
#   export DEPLOY_EDGEROUTER_USER="acmeuser"
#   acme.sh --deploy -d example.com --deploy-hook edgerouter

edgerouter_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _getdeployconf DEPLOY_EDGEROUTER_HOST
  _getdeployconf DEPLOY_EDGEROUTER_PORT
  _getdeployconf DEPLOY_EDGEROUTER_USER

  DEPLOY_EDGEROUTER_HOST="${DEPLOY_EDGEROUTER_HOST:-192.168.0.1}"
  DEPLOY_EDGEROUTER_PORT="${DEPLOY_EDGEROUTER_PORT:-22}"

  if [ -z "$DEPLOY_EDGEROUTER_USER" ]; then
    _err "DEPLOY_EDGEROUTER_USER must be set."
    return 1
  fi

  _ssh_base="-o StrictHostKeyChecking=accept-new"
  _ssh_opts="$_ssh_base -p $DEPLOY_EDGEROUTER_PORT"
  _ssh_target="$DEPLOY_EDGEROUTER_USER@$DEPLOY_EDGEROUTER_HOST"

  _info "Deploying certificate to EdgeRouter at $DEPLOY_EDGEROUTER_HOST..."

  # server.pem = key + leaf cert (ca-file provides the chain separately)
  # shellcheck disable=SC2086
  if ! cat "$_ckey" "$_ccert" | ssh -q $_ssh_opts "$_ssh_target" 'sudo tee /config/ssl/server.pem > /dev/null'; then
    _err "Failed to write server.pem to EdgeRouter."
    return 1
  fi

  # shellcheck disable=SC2086
  if ! cat "$_cca" | ssh -q $_ssh_opts "$_ssh_target" 'sudo tee /config/ssl/ca.cer > /dev/null'; then
    _err "Failed to write ca.cer to EdgeRouter."
    return 1
  fi

  _info "Restarting lighttpd..."
  # shellcheck disable=SC2086
  if ! ssh -q $_ssh_opts "$_ssh_target" 'sudo killall lighttpd 2>/dev/null; sleep 1; sudo /usr/sbin/lighttpd -f /etc/lighttpd/lighttpd.conf'; then
    _err "Certificate files deployed but lighttpd restart failed."
    return 1
  fi

  _savedeployconf DEPLOY_EDGEROUTER_HOST "$DEPLOY_EDGEROUTER_HOST"
  _savedeployconf DEPLOY_EDGEROUTER_PORT "$DEPLOY_EDGEROUTER_PORT"
  _savedeployconf DEPLOY_EDGEROUTER_USER "$DEPLOY_EDGEROUTER_USER"

  _info "EdgeRouter certificate deployed and lighttpd restarted successfully."
  return 0
}
