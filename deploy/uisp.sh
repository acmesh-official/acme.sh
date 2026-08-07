#!/usr/bin/env sh
# Deploy hook for UISP (nico640/docker-unms container image).
#
# Copies the fullchain and key to the usercert directory, then
# restarts the container so refresh-certificate.sh picks them up
# and updates the live.crt/live.key symlinks. Works under either
# podman or docker via DEPLOY_UISP_CONTAINER_CMD.
#
# Settings (required on first run, saved afterward):
#   DEPLOY_UISP_USERCERT_DIR   - Path to usercert directory (e.g. "/Users/acmeuser/uisp/usercert")
#   DEPLOY_UISP_CONTAINER      - Container name (e.g. "uisp")
#   DEPLOY_UISP_CONTAINER_CMD  - Container engine command (default: "podman")
#   DEPLOY_UISP_STOP_TIMEOUT   - Seconds to wait for graceful container stop (default: "30")
#
# Example:
#   export DEPLOY_UISP_USERCERT_DIR="/Users/acmeuser/uisp/usercert"
#   export DEPLOY_UISP_CONTAINER="uisp"
#   acme.sh --deploy -d example.com --deploy-hook uisp
#
# Please report bugs to https://github.com/acmesh-official/acme.sh/issues/7181

uisp_deploy() {
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

  _getdeployconf DEPLOY_UISP_CONTAINER_CMD
  DEPLOY_UISP_CONTAINER_CMD="${DEPLOY_UISP_CONTAINER_CMD:-podman}"
  if ! _exists "$DEPLOY_UISP_CONTAINER_CMD"; then
    _err "$DEPLOY_UISP_CONTAINER_CMD is required for the uisp deploy hook but was not found."
    return 1
  fi
  _savedeployconf DEPLOY_UISP_CONTAINER_CMD "$DEPLOY_UISP_CONTAINER_CMD"

  _getdeployconf DEPLOY_UISP_USERCERT_DIR
  if [ -z "$DEPLOY_UISP_USERCERT_DIR" ]; then
    _err "DEPLOY_UISP_USERCERT_DIR is not set."
    return 1
  fi
  _savedeployconf DEPLOY_UISP_USERCERT_DIR "$DEPLOY_UISP_USERCERT_DIR"

  _getdeployconf DEPLOY_UISP_CONTAINER
  if [ -z "$DEPLOY_UISP_CONTAINER" ]; then
    _err "DEPLOY_UISP_CONTAINER is not set."
    return 1
  fi
  _savedeployconf DEPLOY_UISP_CONTAINER "$DEPLOY_UISP_CONTAINER"

  _getdeployconf DEPLOY_UISP_STOP_TIMEOUT
  DEPLOY_UISP_STOP_TIMEOUT="${DEPLOY_UISP_STOP_TIMEOUT:-30}"
  _savedeployconf DEPLOY_UISP_STOP_TIMEOUT "$DEPLOY_UISP_STOP_TIMEOUT"

  if ! mkdir -p "$DEPLOY_UISP_USERCERT_DIR"; then
    _err "Failed to create $DEPLOY_UISP_USERCERT_DIR"
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

  if ! "$DEPLOY_UISP_CONTAINER_CMD" stop -t "$DEPLOY_UISP_STOP_TIMEOUT" "$DEPLOY_UISP_CONTAINER"; then
    _err "Failed to stop UISP container."
    return 1
  fi

  if ! "$DEPLOY_UISP_CONTAINER_CMD" start "$DEPLOY_UISP_CONTAINER"; then
    _err "Failed to start UISP container."
    return 1
  fi

  _info "UISP certificate deployed and container restarted successfully."
  return 0
}
