#!/usr/bin/env sh

# Deploy-hook to very simply copy files to set directories and then
# execute whatever reloadcmd the admin needs afterwards. This can be
# useful for configurations where the "multideploy" hook (in development)
# is used or when an admin wants ACME.SH to renew certs but needs to
# manually configure deployment via an external script
# (e.g. The deploy-freenas script for TrueNAS Core/Scale
# https://github.com/danb35/deploy-freenas/ )
#
# If the same file is configured for the certificate key
# and the certificate and/or full chain, a combined PEM file will
# be output instead.
#
# Environment variables to be utilized are as follows:
#
# DEPLOY_LOCALCOPY_CERTKEY - /path/to/target/cert.key
# DEPLOY_LOCALCOPY_CERTIFICATE - /path/to/target/cert.cer
# DEPLOY_LOCALCOPY_FULLCHAIN - /path/to/target/fullchain.cer
# DEPLOY_LOCALCOPY_CA - /path/to/target/ca.cer
# DEPLOY_LOCALCOPY_PFX - /path/to/target/cert.pfx
# DEPLOY_LOCALCOPY_RELOADCMD - "echo 'this is my cmd'"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
localcopy_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _cpfx="$6"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug _cpfx "$_cpfx"

  _getdeployconf DEPLOY_LOCALCOPY_CERTIFICATE
  _getdeployconf DEPLOY_LOCALCOPY_CERTKEY
  _getdeployconf DEPLOY_LOCALCOPY_FULLCHAIN
  _getdeployconf DEPLOY_LOCALCOPY_CA
  _getdeployconf DEPLOY_LOCALCOPY_RELOADCMD
  _getdeployconf DEPLOY_LOCALCOPY_PFX
  _combined_target=""
  _combined_srccert=""

  # Create PEM file
  if [ "$DEPLOY_LOCALCOPY_CERTKEY" ] &&
    { [ "$DEPLOY_LOCALCOPY_CERTKEY" = "$DEPLOY_LOCALCOPY_FULLCHAIN" ] ||
      [ "$DEPLOY_LOCALCOPY_CERTKEY" = "$DEPLOY_LOCALCOPY_CERTIFICATE" ]; }; then

    _combined_target="$DEPLOY_LOCALCOPY_CERTKEY"
    _savedeployconf DEPLOY_LOCALCOPY_CERTKEY "$DEPLOY_LOCALCOPY_CERTKEY"
    if [ "$DEPLOY_LOCALCOPY_CERTKEY" = "$DEPLOY_LOCALCOPY_CERTIFICATE" ]; then
      _combined_srccert="$_ccert"
      _savedeployconf DEPLOY_LOCALCOPY_CERTIFICATE "$DEPLOY_LOCALCOPY_CERTIFICATE"
      DEPLOY_LOCALCOPY_CERTIFICATE=""
    fi
    if [ "$DEPLOY_LOCALCOPY_CERTKEY" = "$DEPLOY_LOCALCOPY_FULLCHAIN" ]; then
      _combined_srccert="$_cfullchain"
      _savedeployconf DEPLOY_LOCALCOPY_FULLCHAIN "$DEPLOY_LOCALCOPY_FULLCHAIN"
      DEPLOY_LOCALCOPY_FULLCHAIN=""
    fi
    DEPLOY_LOCALCOPY_CERTKEY=""
    _info "Creating combined PEM"
    _debug "Creating combined PEM at $_combined_target"
    if ! [ -f "$_combined_target" ]; then
      touch "$_combined_target" || return 1
      chmod 600 "$_combined_target"
    fi
    if ! cat "$_combined_srccert" "$_ckey" >"$_combined_target"; then
      _err "Failed to create PEM file"
      return 1
    fi
  fi

  if [ "$DEPLOY_LOCALCOPY_CERTIFICATE" ]; then
    _info "Copying certificate"
    _debug "Copying $_ccert to $DEPLOY_LOCALCOPY_CERTIFICATE"
    if ! cat "$_ccert" >"$DEPLOY_LOCALCOPY_CERTIFICATE"; then
      _err "Failed to copy certificate, aborting."
      return 1
    fi
    _savedeployconf DEPLOY_LOCALCOPY_CERTIFICATE "$DEPLOY_LOCALCOPY_CERTIFICATE"
  fi

  if [ "$DEPLOY_LOCALCOPY_CERTKEY" ]; then
    _info "Copying certificate key"
    _debug "Copying $_ckey to $DEPLOY_LOCALCOPY_CERTKEY"
    if ! [ -f "$DEPLOY_LOCALCOPY_CERTKEY" ]; then
      touch "$DEPLOY_LOCALCOPY_CERTKEY" || return 1
      chmod 600 "$DEPLOY_LOCALCOPY_CERTKEY"
    fi
    if ! cat "$_ckey" >"$DEPLOY_LOCALCOPY_CERTKEY"; then
      _err "Failed to copy certificate key, aborting."
      return 1
    fi
    _savedeployconf DEPLOY_LOCALCOPY_CERTKEY "$DEPLOY_LOCALCOPY_CERTKEY"
  fi

  if [ "$DEPLOY_LOCALCOPY_FULLCHAIN" ]; then
    _info "Copying fullchain"
    _debug "Copying $_cfullchain to $DEPLOY_LOCALCOPY_FULLCHAIN"
    if ! cat "$_cfullchain" >"$DEPLOY_LOCALCOPY_FULLCHAIN"; then
      _err "Failed to copy fullchain, aborting."
      return 1
    fi
    _savedeployconf DEPLOY_LOCALCOPY_FULLCHAIN "$DEPLOY_LOCALCOPY_FULLCHAIN"
  fi

  if [ "$DEPLOY_LOCALCOPY_CA" ]; then
    _info "Copying CA"
    _debug "Copying $_cca to $DEPLOY_LOCALCOPY_CA"
    if ! cat "$_cca" >"$DEPLOY_LOCALCOPY_CA"; then
      _err "Failed to copy CA, aborting."
      return 1
    fi
    _savedeployconf DEPLOY_LOCALCOPY_CA "$DEPLOY_LOCALCOPY_CA"
  fi

  if [ "$DEPLOY_LOCALCOPY_PFX" ]; then
    _info "Copying PFX"
    _debug "Copying $_cpfx to $DEPLOY_LOCALCOPY_PFX"
    if ! [ -f "$DEPLOY_LOCALCOPY_PFX" ]; then
      touch "$DEPLOY_LOCALCOPY_PFX" || return 1
      chmod 600 "$DEPLOY_LOCALCOPY_PFX"
    fi
    if ! cat "$_cpfx" >"$DEPLOY_LOCALCOPY_PFX"; then
      _err "Failed to copy PFX, aborting."
      return 1
    fi
    _savedeployconf DEPLOY_LOCALCOPY_PFX "$DEPLOY_LOCALCOPY_PFX"
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
