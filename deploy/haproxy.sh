#!/usr/bin/env sh

#Here is a script to deploy cert to haproxy server.

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
haproxy_deploy() {
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

  # combine the key and fullchain into a single pem and install
  _savedomainconf DEPLOY_HAPROXY_PEM_PATH "$DEPLOY_HAPROXY_PEM_PATH"

  _pem_path="${DEPLOY_HAPROXY_PEM_PATH}"
  if [ -z "$_pem_path" ]; then
    _err "Path to save PEM file not found. Please define DEPLOY_HAPROXY_PEM_PATH."
    return 1
  fi
  _pem_full_path="$_pem_path/$_cdomain.pem"
  _info "Full path to PEM $_pem_full_path"

  cat "$_cfullchain" "$_ckey" >"$_pem_full_path"
  chmod 600 "$_pem_full_path"

  _info "Certificate successfully deployed"
  return 0

}
