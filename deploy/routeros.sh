#!/usr/bin/env bash

#Here is a script to deploy cert to routeros router.

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
routeros_deploy() {
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

  if [ -z "$ROUTER_OS_HOST" ]; then
    _debug "Using _cdomain as ROUTER_OS_HOST, please set if not correct."
    ROUTER_OS_HOST="$_cdomain"
  fi

  if [ -z "$ROUTER_OS_USERNAME" ]; then
    _err "Need to set the env variable ROUTER_OS_USERNAME"
    return 1
  fi

  _info "Trying to push key '$_ckey' to router"
  scp "$_ckey" "$ROUTER_OS_USERNAME@$ROUTER_OS_HOST:$_cdomain.key"
  _info "Trying to push cert '$_ccert' to router"
  scp "$_ccert" "$ROUTER_OS_USERNAME@$ROUTER_OS_HOST:$_cdomain.cer"
  _info "Trying to push ca cert '$_cca' to router"
  scp "$_cca" "$ROUTER_OS_USERNAME@$ROUTER_OS_HOST:$_cdomain.ca"
  # shellcheck disable=SC2029
  ssh "$ROUTER_OS_USERNAME@$ROUTER_OS_HOST" bash -c "'

/certificate remove $_cdomain.cer_0

/certificate remove $_cdomain.cer_1

/certificate remove $_cdomain.ca_0

delay 1

/certificate import file-name=$_cdomain.cer passphrase=\"\"

/certificate import file-name=$_cdomain.key passphrase=\"\"

/certificate import file-name=$_cdomain.ca passphrase=\"\"

delay 1

/file remove $_cdomain.cer

/file remove $_cdomain.key

/file remove $_cdomain.ca

delay 2

/ip service set www-ssl certificate=$_cdomain.cer_0

'"
  return 0
}
