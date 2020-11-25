#!/usr/bin/env sh

# Here is a script to deploy cert to hashicorp vault using curl
# (https://www.vaultproject.io/)
#
# it requires following environment variables:
#
# VAULT_PREFIX - this contains the prefix path in vault
# VAULT_ADDR - vault requires this to find your vault server
#
# additionally, you need to ensure that VAULT_TOKEN is avialable
# to access the vault server

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
vault_deploy() {

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

  # JSON does not allow multiline strings.
  # So replacing new-lines with "\n" here
  _ckey=$(sed -z 's/\n/\\n/g' <"$2")
  _ccert=$(sed -z 's/\n/\\n/g' <"$3")
  _cca=$(sed -z 's/\n/\\n/g' <"$4")
  _cfullchain=$(sed -z 's/\n/\\n/g' <"$5")

  URL="$VAULT_ADDR/v1/$VAULT_PREFIX/$_cdomain"
  export _H1="X-Vault-Token: $VAULT_TOKEN"

  if [ -n "$FABIO" ]; then
    _post "{\"cert\": \"$_cfullchain\", \"key\": \"$_ckey\"}" "$URL"
  else
    _post "{\"value\": \"$_ccert\"}" "$URL/cert.pem"
    _post "{\"value\": \"$_ckey\"}" "$URL/cert.key"
    _post "{\"value\": \"$_cca\"}" "$URL/chain.pem"
    _post "{\"value\": \"$_cfullchain\"}" "$URL/fullchain.pem"
  fi

}
