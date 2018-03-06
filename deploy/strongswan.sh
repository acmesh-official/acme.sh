#!/usr/bin/env sh

#Here is a sample custom api script.
#This file name is "myapi.sh"
#So, here must be a method   myapi_deploy()
#Which will be called by acme.sh to deploy the cert
#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
strongswan_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _info "Using strongswan"

  if [ -x /usr/sbin/ipsec ]; then
    _ipsec=/usr/sbin/ipsec
  elif [ -x /usr/sbin/strongswan ]; then
    _ipsec=/usr/sbin/strongswan
  elif [ -x /usr/local/sbin/ipsec ]; then
    _ipsec=/usr/local/sbin/ipsec
  else
    _err "no strongswan or ipsec command is detected"
    return 1
  fi

  _info _ipsec "$_ipsec"

  _confdir=$($_ipsec --confdir)
  if [ $? -ne 0 ] || [ -z "$_confdir" ]; then
    _err "no strongswan --confdir is detected"
    return 1
  fi

  _info _confdir "$_confdir"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  cat "$_ckey" >"${_confdir}/ipsec.d/private/$(basename "$_ckey")"
  cat "$_ccert" >"${_confdir}/ipsec.d/certs/$(basename "$_ccert")"
  cat "$_cca" >"${_confdir}/ipsec.d/cacerts/$(basename "$_cca")"
  cat "$_cfullchain" >"${_confdir}/ipsec.d/cacerts/$(basename "$_cfullchain")"

  $_ipsec reload

}
