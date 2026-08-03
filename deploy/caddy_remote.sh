#!/usr/bin/env sh
# Deploy hook for a remote Caddy instance via SSH.
#
# Deploys cert files to a remote host via SSH + sudo tee, fixes ownership
# to caddy:caddy mode 640, then reloads Caddy via systemctl. Designed for
# hosts where Caddy runs as a systemd service under the `caddy` user.
#
# Settings:
#   DEPLOY_CADDY_REMOTE_USER - SSH username (required)
#   DEPLOY_CADDY_REMOTE_HOST - SSH hostname or IP (required)
#   DEPLOY_CADDY_REMOTE_CERT_DIR - remote cert directory (default: "/etc/caddy/certs")
#
# Example:
#   export DEPLOY_CADDY_REMOTE_USER="acmeuser"
#   export DEPLOY_CADDY_REMOTE_HOST="192.168.1.30"
#   acme.sh --deploy -d example.com --deploy-hook caddy_remote

caddy_remote_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _getdeployconf DEPLOY_CADDY_REMOTE_USER
  if [ -z "$DEPLOY_CADDY_REMOTE_USER" ]; then
    _err "DEPLOY_CADDY_REMOTE_USER is required."
    return 1
  fi

  _getdeployconf DEPLOY_CADDY_REMOTE_HOST
  if [ -z "$DEPLOY_CADDY_REMOTE_HOST" ]; then
    _err "DEPLOY_CADDY_REMOTE_HOST is required."
    return 1
  fi

  _getdeployconf DEPLOY_CADDY_REMOTE_CERT_DIR
  if [ -z "$DEPLOY_CADDY_REMOTE_CERT_DIR" ]; then
    DEPLOY_CADDY_REMOTE_CERT_DIR="/etc/caddy/certs"
  fi

  _cr_ssh_target="$DEPLOY_CADDY_REMOTE_USER@$DEPLOY_CADDY_REMOTE_HOST"
  _cr_ssh_opts="-o BatchMode=yes -o StrictHostKeyChecking=accept-new"

  _info "Deploying certificate to $DEPLOY_CADDY_REMOTE_HOST..."

  # Deploy fullchain
  # shellcheck disable=SC2086,SC2029
  if ! cat "$_cfullchain" | ssh $_cr_ssh_opts "$_cr_ssh_target" "sudo tee $DEPLOY_CADDY_REMOTE_CERT_DIR/fullchain.cer > /dev/null"; then
    _err "Failed to copy fullchain.cer to $DEPLOY_CADDY_REMOTE_HOST."
    return 1
  fi

  # Deploy key
  # shellcheck disable=SC2086,SC2029
  if ! cat "$_ckey" | ssh $_cr_ssh_opts "$_cr_ssh_target" "sudo tee $DEPLOY_CADDY_REMOTE_CERT_DIR/key.key > /dev/null"; then
    _err "Failed to copy key.key to $DEPLOY_CADDY_REMOTE_HOST."
    return 1
  fi

  # Fix ownership and permissions
  # shellcheck disable=SC2086,SC2029
  if ! ssh $_cr_ssh_opts "$_cr_ssh_target" "sudo chown caddy:caddy $DEPLOY_CADDY_REMOTE_CERT_DIR/fullchain.cer $DEPLOY_CADDY_REMOTE_CERT_DIR/key.key && sudo chmod 640 $DEPLOY_CADDY_REMOTE_CERT_DIR/fullchain.cer $DEPLOY_CADDY_REMOTE_CERT_DIR/key.key"; then
    _err "Failed to set ownership/permissions on $DEPLOY_CADDY_REMOTE_HOST cert files."
    return 1
  fi

  # Reload Caddy
  # shellcheck disable=SC2086
  if ! ssh $_cr_ssh_opts "$_cr_ssh_target" "sudo systemctl reload caddy"; then
    _err "Failed to reload Caddy on $DEPLOY_CADDY_REMOTE_HOST."
    return 1
  fi

  _savedeployconf DEPLOY_CADDY_REMOTE_USER "$DEPLOY_CADDY_REMOTE_USER"
  _savedeployconf DEPLOY_CADDY_REMOTE_HOST "$DEPLOY_CADDY_REMOTE_HOST"
  _savedeployconf DEPLOY_CADDY_REMOTE_CERT_DIR "$DEPLOY_CADDY_REMOTE_CERT_DIR"

  _info "Certificate deployed and Caddy reloaded on $DEPLOY_CADDY_REMOTE_HOST successfully."
  return 0
}
