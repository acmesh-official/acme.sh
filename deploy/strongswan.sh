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

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  cat "$_ckey" >"/etc/ipsec.d/private/$(basename "$_ckey")"
  cat "$_ccert" >"/etc/ipsec.d/certs/$(basename "$_ccert")"
  cat "$_cca" >"/etc/ipsec.d/cacerts/$(basename "$_cca")"
  cat "$_cfullchain" >"/etc/ipsec.d/cacerts/$(basename "$_cfullchain")"

  ipsec reload

}
