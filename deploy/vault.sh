#!/usr/bin/env sh

# Here is a script to deploy cert to hashicorp vault using curl
# (https://www.vaultproject.io/)
#
# it requires following environment variables:
#
# VAULT_PREFIX - this contains the prefix path in vault
# VAULT_ADDR - vault requires this to find your vault server
# VAULT_SAVE_TOKEN - set to anything if you want to save the token
# VAULT_RENEW_TOKEN - set to anything if you want to renew the token to default TTL before deploying
# VAULT_KV_V2 - set to anything if you are using v2 of the kv engine
#
# additionally, you need to ensure that VAULT_TOKEN is avialable
# to access the vault server

#returns 0 means success, otherwise error.

######## Public functions #####################

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

  _getdeployconf VAULT_SAVE_TOKEN
  _savedeployconf VAULT_SAVE_TOKEN "$VAULT_SAVE_TOKEN"

  _getdeployconf VAULT_RENEW_TOKEN
  _savedeployconf VAULT_RENEW_TOKEN "$VAULT_RENEW_TOKEN"

  _getdeployconf VAULT_KV_V2
  _savedeployconf VAULT_KV_V2 "$VAULT_KV_V2"

  _getdeployconf VAULT_TOKEN
  if [ -z "$VAULT_TOKEN" ]; then
    _err "VAULT_TOKEN needs to be defined"
    return 1
  fi
  if [ -n "$VAULT_SAVE_TOKEN" ]; then
    _savedeployconf VAULT_TOKEN "$VAULT_TOKEN"
  fi

  _migratedeployconf FABIO VAULT_FABIO_MODE

  # JSON does not allow multiline strings.
  # So replacing new-lines with "\n" here
  _ckey=$(sed -e ':a' -e N -e '$ ! ba' -e 's/\n/\\n/g' <"$2")
  _ccert=$(sed -e ':a' -e N -e '$ ! ba' -e 's/\n/\\n/g' <"$3")
  _cca=$(sed -e ':a' -e N -e '$ ! ba' -e 's/\n/\\n/g' <"$4")
  _cfullchain=$(sed -e ':a' -e N -e '$ ! ba' -e 's/\n/\\n/g' <"$5")

  export _H1="X-Vault-Token: $VAULT_TOKEN"

  if [ -n "$VAULT_RENEW_TOKEN" ]; then
    URL="$VAULT_ADDR/v1/auth/token/renew-self"
    _info "Renew the Vault token to default TTL"
    _response=$(_post "" "$URL")
    if [ "$?" != "0" ]; then
      _err "Failed to renew the Vault token"
      return 1
    fi
    if echo "$_response" | grep -q '"errors":\['; then
      _err "Failed to renew the Vault token: $_response"
      return 1
    fi
  fi

  URL="$VAULT_ADDR/v1/$VAULT_PREFIX/$_cdomain"

  if [ -n "$VAULT_FABIO_MODE" ]; then
    _info "Writing certificate and key to $URL in Fabio mode"
    if [ -n "$VAULT_KV_V2" ]; then
      _response=$(_post "{ \"data\": {\"cert\": \"$_cfullchain\", \"key\": \"$_ckey\"} }" "$URL")
      if [ "$?" != "0" ]; then return 1; fi
      if echo "$_response" | grep -q '"errors":\['; then
        _err "Vault error: $_response"
        return 1
      fi
    else
      _response=$(_post "{\"cert\": \"$_cfullchain\", \"key\": \"$_ckey\"}" "$URL")
      if [ "$?" != "0" ]; then return 1; fi
      if echo "$_response" | grep -q '"errors":\['; then
        _err "Vault error: $_response"
        return 1
      fi
    fi
  else
    if [ -n "$VAULT_KV_V2" ]; then
      _info "Writing certificate to $URL/cert.pem"
      _response=$(_post "{\"data\": {\"value\": \"$_ccert\"}}" "$URL/cert.pem")
      if [ "$?" != "0" ]; then return 1; fi
      if echo "$_response" | grep -q '"errors":\['; then
        _err "Vault error writing cert.pem: $_response"
        return 1
      fi

      _info "Writing key to $URL/cert.key"
      _response=$(_post "{\"data\": {\"value\": \"$_ckey\"}}" "$URL/cert.key")
      if [ "$?" != "0" ]; then return 1; fi
      if echo "$_response" | grep -q '"errors":\['; then
        _err "Vault error writing cert.key: $_response"
        return 1
      fi

      _info "Writing CA certificate to $URL/ca.pem"
      _response=$(_post "{\"data\": {\"value\": \"$_cca\"}}" "$URL/ca.pem")
      if [ "$?" != "0" ]; then return 1; fi
      if echo "$_response" | grep -q '"errors":\['; then
        _err "Vault error writing ca.pem: $_response"
        return 1
      fi

      _info "Writing full-chain certificate to $URL/fullchain.pem"
      _response=$(_post "{\"data\": {\"value\": \"$_cfullchain\"}}" "$URL/fullchain.pem")
      if [ "$?" != "0" ]; then return 1; fi
      if echo "$_response" | grep -q '"errors":\['; then
        _err "Vault error writing fullchain.pem: $_response"
        return 1
      fi
    else
      _info "Writing certificate to $URL/cert.pem"
      _response=$(_post "{\"value\": \"$_ccert\"}" "$URL/cert.pem")
      if [ "$?" != "0" ]; then return 1; fi
      if echo "$_response" | grep -q '"errors":\['; then
        _err "Vault error writing cert.pem: $_response"
        return 1
      fi

      _info "Writing key to $URL/cert.key"
      _response=$(_post "{\"value\": \"$_ckey\"}" "$URL/cert.key")
      if [ "$?" != "0" ]; then return 1; fi
      if echo "$_response" | grep -q '"errors":\['; then
        _err "Vault error writing cert.key: $_response"
        return 1
      fi

      _info "Writing CA certificate to $URL/ca.pem"
      _response=$(_post "{\"value\": \"$_cca\"}" "$URL/ca.pem")
      if [ "$?" != "0" ]; then return 1; fi
      if echo "$_response" | grep -q '"errors":\['; then
        _err "Vault error writing ca.pem: $_response"
        return 1
      fi

      _info "Writing full-chain certificate to $URL/fullchain.pem"
      _response=$(_post "{\"value\": \"$_cfullchain\"}" "$URL/fullchain.pem")
      if [ "$?" != "0" ]; then return 1; fi
      if echo "$_response" | grep -q '"errors":\['; then
        _err "Vault error writing fullchain.pem: $_response"
        return 1
      fi
    fi

    # To make it compatible with the wrong ca path `chain.pem` which was used in former versions
    if _contains "$(_get "$URL/chain.pem")" "-----BEGIN CERTIFICATE-----"; then
      _err "The CA certificate has moved from chain.pem to ca.pem, if you don't depend on chain.pem anymore, you can delete it to avoid this warning"
      _info "Updating CA certificate to $URL/chain.pem for backward compatibility"
      if [ -n "$VAULT_KV_V2" ]; then
        _response=$(_post "{\"data\": {\"value\": \"$_cca\"}}" "$URL/chain.pem")
        if [ "$?" != "0" ]; then return 1; fi
        if echo "$_response" | grep -q '"errors":\['; then
          _err "Vault error writing chain.pem: $_response"
          return 1
        fi
      else
        _response=$(_post "{\"value\": \"$_cca\"}" "$URL/chain.pem")
        if [ "$?" != "0" ]; then return 1; fi
        if echo "$_response" | grep -q '"errors":\['; then
          _err "Vault error writing chain.pem: $_response"
          return 1
        fi
      fi
    fi
  fi
}
