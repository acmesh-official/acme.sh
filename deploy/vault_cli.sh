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

  # JSON does not allow multiline strings.
  # So replacing new-lines with "\n" here
  _ckey=$(sed -z 's/\n/\\n/g' < "$2")
  _ccert=$(sed -z 's/\n/\\n/g' < "$3")
  _cca=$(sed -z 's/\n/\\n/g' < "$4")
  _cfullchain=$(sed -z 's/\n/\\n/g' < "$5")

  URL="$VAULT_ADDR/v1/$VAULT_PREFIX/$_cdomain"

  if [ -n "$FABIO" ]; then
    curl --silent -H "X-Vault-Token: $VAULT_TOKEN" --request POST --data "{\"cert\": \"$_cfullchain\", \"key\": \"$_ckey\"}" "$URL" || return 1
  else
    curl --silent -H "X-Vault-Token: $VAULT_TOKEN" --request POST --data "{\"value\": \"$_ccert\"}"      "$URL/cert.pem" || return 1
    curl --silent -H "X-Vault-Token: $VAULT_TOKEN" --request POST --data "{\"value\": \"$_ckey\"}"       "$URL/cert.key" || return 1
    curl --silent -H "X-Vault-Token: $VAULT_TOKEN" --request POST --data "{\"value\": \"$_cca\"}"        "$URL/chain.pem" || return 1
    curl --silent -H "X-Vault-Token: $VAULT_TOKEN" --request POST --data "{\"value\": \"$_cfullchain\"}" "$URL/fullchain.pem" || return 1
  fi

}
