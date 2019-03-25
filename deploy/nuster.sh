#!/usr/bin/env sh

#Here is a script to deploy cert to nuster server.

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
nuster_deploy() {
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

  # handle reload preference
  DEFAULT_NUSTER_RELOAD="/usr/sbin/service nuster restart"
  if [ -z "${DEPLOY_NUSTER_RELOAD}" ]; then
    _reload="${DEFAULT_NUSTER_RELOAD}"
    _cleardomainconf DEPLOY_NUSTER_RELOAD
  else
    _reload="${DEPLOY_NUSTER_RELOAD}"
    _savedomainconf DEPLOY_NUSTER_RELOAD "$DEPLOY_NUSTER_RELOAD"
  fi
  _savedomainconf DEPLOY_NUSTER_PEM_PATH "$DEPLOY_NUSTER_PEM_PATH"

  # work out the path where the PEM file should go
  _pem_path="${DEPLOY_NUSTER_PEM_PATH}"
  if [ -z "$_pem_path" ]; then
    _err "Path to save PEM file not found. Please define DEPLOY_NUSTER_PEM_PATH."
    return 1
  fi
  _pem_full_path="$_pem_path/$_cdomain.pem"
  _info "Full path to PEM $_pem_full_path"

  # combine the key and fullchain into a single pem and install
  cat "$_cfullchain" "$_ckey" >"$_pem_full_path"
  chmod 600 "$_pem_full_path"
  _info "Certificate successfully deployed"

  # restart nuster
  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
    return 0
  else
    _err "Reload error"
    return 1
  fi

}
