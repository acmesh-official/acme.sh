#!/usr/bin/env sh
# Deploy hook for UISP (nico640/docker-unms Podman container).
#
# Copies the fullchain and key to the usercert directory, then
# restarts the container so refresh-certificate.sh picks them up
# and updates the live.crt/live.key symlinks.
#
# Settings (required on first run, saved afterward):
#   DEPLOY_UISP_USERCERT_DIR  - Path to usercert directory (e.g. "/Users/acmeuser/uisp/usercert")
#   DEPLOY_UISP_CONTAINER     - Container name (e.g. "uisp")
#
# Example:
#   export DEPLOY_UISP_USERCERT_DIR="/Users/acmeuser/uisp/usercert"
#   export DEPLOY_UISP_CONTAINER="uisp"
#   acme.sh --deploy -d example.com --deploy-hook uisp

uisp_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _getdeployconf DEPLOY_UISP_USERCERT_DIR
  _getdeployconf DEPLOY_UISP_CONTAINER

  if [ -z "$DEPLOY_UISP_USERCERT_DIR" ]; then
    _err "DEPLOY_UISP_USERCERT_DIR is not set."
    return 1
  fi

  if [ -z "$DEPLOY_UISP_CONTAINER" ]; then
    _err "DEPLOY_UISP_CONTAINER is not set."
    return 1
  fi

  _info "Deploying certificate to UISP usercert at $DEPLOY_UISP_USERCERT_DIR..."

  if ! cp "$_cfullchain" "$DEPLOY_UISP_USERCERT_DIR/custom.crt"; then
    _err "Failed to copy fullchain to $DEPLOY_UISP_USERCERT_DIR/custom.crt"
    return 1
  fi

  if ! cp "$_ckey" "$DEPLOY_UISP_USERCERT_DIR/custom.key"; then
    _err "Failed to copy key to $DEPLOY_UISP_USERCERT_DIR/custom.key"
    return 1
  fi

  _info "Restarting UISP container '$DEPLOY_UISP_CONTAINER'..."

  if ! podman stop -t 120 "$DEPLOY_UISP_CONTAINER"; then
    _err "Failed to stop UISP container."
    return 1
  fi

  if ! podman start "$DEPLOY_UISP_CONTAINER"; then
    _err "Failed to start UISP container."
    return 1
  fi

  _savedeployconf DEPLOY_UISP_USERCERT_DIR "$DEPLOY_UISP_USERCERT_DIR"
  _savedeployconf DEPLOY_UISP_CONTAINER "$DEPLOY_UISP_CONTAINER"

  _info "UISP certificate deployed and container restarted successfully."
  return 0
}
