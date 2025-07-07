#!/usr/bin/env sh

# Deploy-hook to very simply copy files to set directories and then
# execute whatever reloadcmd the admin needs afterwards. This can be
# useful for configurations where the "multideploy" hook (in development)
# is used or when an admin wants ACME.SH to renew certs but needs to
# manually configure deployment via an external script
# (e.g. The deploy-freenas script for TrueNAS Core/Scale
# https://github.com/danb35/deploy-freenas/ )
#
#
# Environment variables to be utilized are as follows:
#
# DEPLOY_LOCALCOPY_CERTIFICATE - /path/to/target/cert.cer
# DEPLOY_LOCALCOPY_CERTKEY - /path/to/target/cert.key
# DEPLOY_LOCALCOPY_FULLCHAIN - /path/to/target/fullchain.cer
# DEPLOY_LOCALCOPY_CA - /path/to/target/ca.cer
# DEPLOY_LOCALCOPY_RELOADCMD - "echo 'this is my cmd'"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
localcopy_deploy() {
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

  _getdeployconf DEPLOY_LOCALCOPY_CERTIFICATE
  _getdeployconf DEPLOY_LOCALCOPY_CERTKEY
  _getdeployconf DEPLOY_LOCALCOPY_FULLCHAIN
  _getdeployconf DEPLOY_LOCALCOPY_CA
  _getdeployconf DEPLOY_LOCALCOPY_RELOADCMD

  if [ "$DEPLOY_LOCALCOPY_CERTIFICATE" ]; then
    _info "Copying certificate"
    _debug "Copying $_ccert to $DEPLOY_LOCALCOPY_CERTIFICATE"
    if ! eval "cp $_ccert $DEPLOY_LOCALCOPY_CERTIFICATE"; then
      _err "Failed to copy certificate, aborting."
      return 1
    fi
    _savedeployconf DEPLOY_LOCALCOPY_CERTIFICATE "$DEPLOY_LOCALCOPY_CERTIFICATE"
  fi

  if [ "$DEPLOY_LOCALCOPY_CERTKEY" ]; then
    _info "Copying certificate key"
    _debug "Copying $_ckey to $DEPLOY_LOCALCOPY_CERTKEY"
    if ! eval "cp $_ckey $DEPLOY_LOCALCOPY_CERTKEY"; then
      _err "Failed to copy certificate key, aborting."
      return 1
    fi
    _savedeployconf DEPLOY_LOCALCOPY_CERTKEY "$DEPLOY_LOCALCOPY_CERTKEY"
  fi

  if [ "$DEPLOY_LOCALCOPY_FULLCHAIN" ]; then
    _info "Copying fullchain"
    _debug "Copying $_cfullchain to $DEPLOY_LOCALCOPY_FULLCHAIN"
    if ! eval "cp $_cfullchain $DEPLOY_LOCALCOPY_FULLCHAIN"; then
      _err "Failed to copy fullchain, aborting."
      return 1
    fi
    _savedeployconf DEPLOY_LOCALCOPY_FULLCHAIN "$DEPLOY_LOCALCOPY_FULLCHAIN"
  fi

  if [ "$DEPLOY_LOCALCOPY_CA" ]; then
    _info "Copying CA"
    _debug "Copying $_cca to $DEPLOY_LOCALCOPY_CA"
    if ! eval "cp $_cca $DEPLOY_LOCALCOPY_CA"; then
      _err "Failed to copy CA, aborting."
      return 1
    fi
    _savedeployconf DEPLOY_LOCALCOPY_CA "$DEPLOY_LOCALCOPY_CA"
  fi

  _reload=$DEPLOY_LOCALCOPY_RELOADCMD
  _debug "Running reloadcmd $_reload"

  if [ -z "$_reload" ]; then
    _info "Reloadcmd not provided, skipping."
  else
    _info "Reloading"
    if eval "$_reload"; then
      _info "Reload successful."
      _savedeployconf DEPLOY_LOCALCOPY_RELOADCMD "$DEPLOY_LOCALCOPY_RELOADCMD" "base64"
    else
      _err "Reload failed."
      return 1
    fi
  fi

  _info "$(__green "'localcopy' deploy success")"
  return 0
}
