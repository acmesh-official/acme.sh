#!/usr/bin/env sh

#Here is a sample custom api script.
#This file name is "myapi.sh"
#So, here must be a method   myapi_deploy()
#Which will be called by acme.sh to deploy the cert
#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
keychain_deploy() {
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

  /usr/bin/security import "$_ckey" -k "/Library/Keychains/System.keychain"
  /usr/bin/security import "$_ccert" -k "/Library/Keychains/System.keychain"
  /usr/bin/security import "$_cca" -k "/Library/Keychains/System.keychain"
  /usr/bin/security import "$_cfullchain" -k "/Library/Keychains/System.keychain"

  return 0
}
