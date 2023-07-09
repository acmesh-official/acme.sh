#!/usr/bin/env sh

# Here is a script to deploy cert to hashicorp vault
# (https://www.vaultproject.io/)
#
# it requires the vault binary to be available in PATH, and the following
# environment variables:
#
# VAULT_PREFIX - this contains the prefix path in vault
# VAULT_ADDR - vault requires this to find your vault server
# VAULT_SAVE_TOKEN - set to anything if you want to save the token
# VAULT_RENEW_TOKEN - set to anything if you want to renew the token to default TTL before deploying
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
  _getdeployconf VAULT_PREFIX
  if [ -z "$VAULT_PREFIX" ]; then
    _err "VAULT_PREFIX needs to be defined (contains prefix path in vault)"
    return 1
  fi
  _savedeployconf VAULT_PREFIX "$VAULT_PREFIX"

  _getdeployconf VAULT_ADDR
  if [ -z "$VAULT_ADDR" ]; then
    _err "VAULT_ADDR needs to be defined (contains vault connection address)"
    return 1
  fi
  _savedeployconf VAULT_ADDR "$VAULT_ADDR"

  _getdeployconf VAULT_SAVE_TOKEN
  _savedeployconf VAULT_SAVE_TOKEN "$VAULT_SAVE_TOKEN"

  _getdeployconf VAULT_RENEW_TOKEN
  _savedeployconf VAULT_RENEW_TOKEN "$VAULT_RENEW_TOKEN"

  _getdeployconf VAULT_TOKEN
  if [ -z "$VAULT_TOKEN" ]; then
    _err "VAULT_TOKEN needs to be defined"
    return 1
  fi
  if [ -n "$VAULT_SAVE_TOKEN" ]; then
    _savedeployconf VAULT_TOKEN "$VAULT_TOKEN"
  fi

  _migratedeployconf FABIO VAULT_FABIO_MODE

  VAULT_CMD=$(command -v vault)
  if [ ! $? ]; then
    _err "cannot find vault binary!"
    return 1
  fi

  if [ -n "$VAULT_RENEW_TOKEN" ]; then
    _info "Renew the Vault token to default TTL"
    if ! $VAULT_CMD token renew; then
      _err "Failed to renew the Vault token"
      return 1
    fi
  fi

  if [ -n "$VAULT_FABIO_MODE" ]; then
    _info "Writing certificate and key to ${VAULT_PREFIX}/${_cdomain} in Fabio mode"
    $VAULT_CMD kv put "${VAULT_PREFIX}/${_cdomain}" cert=@"$_cfullchain" key=@"$_ckey" || return 1
  else
    _info "Writing certificate to ${VAULT_PREFIX}/${_cdomain}/cert.pem"
    $VAULT_CMD kv put "${VAULT_PREFIX}/${_cdomain}/cert.pem" value=@"$_ccert" || return 1
    _info "Writing key to ${VAULT_PREFIX}/${_cdomain}/cert.key"
    $VAULT_CMD kv put "${VAULT_PREFIX}/${_cdomain}/cert.key" value=@"$_ckey" || return 1
    _info "Writing CA certificate to ${VAULT_PREFIX}/${_cdomain}/ca.pem"
    $VAULT_CMD kv put "${VAULT_PREFIX}/${_cdomain}/ca.pem" value=@"$_cca" || return 1
    _info "Writing full-chain certificate to ${VAULT_PREFIX}/${_cdomain}/fullchain.pem"
    $VAULT_CMD kv put "${VAULT_PREFIX}/${_cdomain}/fullchain.pem" value=@"$_cfullchain" || return 1

    # To make it compatible with the wrong ca path `chain.pem` which was used in former versions
    if $VAULT_CMD kv get "${VAULT_PREFIX}/${_cdomain}/chain.pem" >/dev/null; then
      _err "The CA certificate has moved from chain.pem to ca.pem, if you don't depend on chain.pem anymore, you can delete it to avoid this warning"
      _info "Updating CA certificate to ${VAULT_PREFIX}/${_cdomain}/chain.pem for backward compatibility"
      $VAULT_CMD kv put "${VAULT_PREFIX}/${_cdomain}/chain.pem" value=@"$_cca" || return 1
    fi
  fi

}
