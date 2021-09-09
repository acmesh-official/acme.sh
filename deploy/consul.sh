#!/usr/bin/env sh

# Here is a script to deploy cert to hashicorp consul using curl
# (https://www.consul.io/)
#
# it requires following environment variables:
#
# CONSUL_PREFIX - this contains the prefix path in consul
# CONSUL_HTTP_ADDR - consul requires this to find your consul server
#
# additionally, you need to ensure that CONSUL_HTTP_TOKEN is available
# to access the consul server

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
consul_deploy() {

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
  _getdeployconf CONSUL_PREFIX
  if [ -z "$CONSUL_PREFIX" ]; then
    _err "CONSUL_PREFIX needs to be defined (contains prefix path in vault)"
    return 1
  fi
  _savedeployconf CONSUL_PREFIX "$CONSUL_PREFIX"

  _getdeployconf CONSUL_HTTP_ADDR
  if [ -z "$CONSUL_HTTP_ADDR" ]; then
    _err "CONSUL_HTTP_ADDR needs to be defined (contains consul connection address)"
    return 1
  fi
  _savedeployconf CONSUL_HTTP_ADDR "$CONSUL_HTTP_ADDR"

  CONSUL_CMD=$(command -v consul)

  # force CLI, but the binary does not exist => error
  if [ -n "$USE_CLI" ] && [ -z "$CONSUL_CMD" ]; then
    _err "Cannot find the consul binary!"
    return 1
  fi

  # use the CLI first
  if [ -n "$USE_CLI" ] || [ -n "$CONSUL_CMD" ]; then
    _info "Found consul binary, deploying with CLI"
    consul_deploy_cli "$CONSUL_CMD" "$CONSUL_PREFIX"
  else
    _info "Did not find consul binary, deploying with API"
    consul_deploy_api "$CONSUL_HTTP_ADDR" "$CONSUL_PREFIX" "$CONSUL_HTTP_TOKEN"
  fi
}

consul_deploy_api() {
  CONSUL_HTTP_ADDR="$1"
  CONSUL_PREFIX="$2"
  CONSUL_HTTP_TOKEN="$3"

  URL="$CONSUL_HTTP_ADDR/v1/kv/$CONSUL_PREFIX"
  export _H1="X-Consul-Token: $CONSUL_HTTP_TOKEN"

  if [ -n "$FABIO" ]; then
    _post "$(cat "$_cfullchain")" "$URL/${_cdomain}-cert.pem" '' "PUT" || return 1
    _post "$(cat "$_ckey")" "$URL/${_cdomain}-key.pem" '' "PUT" || return 1
  else
    _post "$(cat "$_ccert")" "$URL/${_cdomain}/cert.pem" '' "PUT" || return 1
    _post "$(cat "$_ckey")" "$URL/${_cdomain}/cert.key" '' "PUT" || return 1
    _post "$(cat "$_cca")" "$URL/${_cdomain}/chain.pem" '' "PUT" || return 1
    _post "$(cat "$_cfullchain")" "$URL/${_cdomain}/fullchain.pem" '' "PUT" || return 1
  fi
}

consul_deploy_cli() {
  CONSUL_CMD="$1"
  CONSUL_PREFIX="$2"

  if [ -n "$FABIO" ]; then
    $CONSUL_CMD kv put "${CONSUL_PREFIX}/${_cdomain}-cert.pem" @"$_cfullchain" || return 1
    $CONSUL_CMD kv put "${CONSUL_PREFIX}/${_cdomain}-key.pem" @"$_ckey" || return 1
  else
    $CONSUL_CMD kv put "${CONSUL_PREFIX}/${_cdomain}/cert.pem" value=@"$_ccert" || return 1
    $CONSUL_CMD kv put "${CONSUL_PREFIX}/${_cdomain}/cert.key" value=@"$_ckey" || return 1
    $CONSUL_CMD kv put "${CONSUL_PREFIX}/${_cdomain}/chain.pem" value=@"$_cca" || return 1
    $CONSUL_CMD kv put "${CONSUL_PREFIX}/${_cdomain}/fullchain.pem" value=@"$_cfullchain" || return 1
  fi
}
