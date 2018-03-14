#!/usr/bin/env sh

#Here is a script to deploy cert to opensshd server.

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
opensshd_deploy() {
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

  _err "deploy cert to opensshd server, Not implemented yet"
  return 1

}
