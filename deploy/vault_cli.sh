#!/usr/bin/env sh

# Here is a script to deploy cert to hashicorp vault
# (https://www.vaultproject.io/)
# 
# it requires the vault binary to be available in PATH, and the following
# environment variables:
# 
# VAULT_PREFIX - this contains the prefix path in vault
# VAULT_ADDR - vault requires this to find your vault server
#
# additionally, you need to ensure that VAULT_TOKEN is avialable or
# `vault auth` has applied the appropriate authorization for the vault binary
# to access the vault server

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
vault_cli_deploy() {

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

  # validate required env vars
  if [ -z "$VAULT_PREFIX" ]; then
    _err "VAULT_PREFIX needs to be defined (contains prefix path in vault)"
    return 1
  fi

  if [ -z "$VAULT_ADDR" ]; then
    _err "VAULT_ADDR needs to be defined (contains vault connection address)"
    return 1
  fi

  VAULT_CMD=$(which vault)
  if [ ! $? ]; then
    _err "cannot find vault binary!"
    return 1
  fi

  if [ -n "$FABIO" ]; then
    $VAULT_CMD write "${VAULT_PREFIX}/${_cdomain}" cert=@"$_cfullchain" key=@"$_ckey" || return 1
  else
    $VAULT_CMD write "${VAULT_PREFIX}/${_cdomain}/cert.pem" value=@"$_ccert" || return 1
    $VAULT_CMD write "${VAULT_PREFIX}/${_cdomain}/cert.key" value=@"$_ckey" || return 1
    $VAULT_CMD write "${VAULT_PREFIX}/${_cdomain}/chain.pem" value=@"$_cca" || return 1
    $VAULT_CMD write "${VAULT_PREFIX}/${_cdomain}/fullchain.pem" value=@"$_cfullchain" || return 1
  fi

}
