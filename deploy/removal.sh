#!/usr/bin/env sh

#Here is a script to remove certs and private key.

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchai
removal_deploy() {
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

  rm -f "$_ckey"
  rm -f "$_ccert"
  rm -f "$_cca"
  rm -f "$_cfullchain"

  return 0
}
