#!/usr/bin/env sh

#Here is the script to deploy the cert to your cpanel account by the cpanel APIs.

#returns 0 means success, otherwise error.

#export DEPLOY_CPANEL_USER=myusername
#export DEPLOY_CPANEL_PASSWORD=PASSWORD

########  Public functions #####################

#domain keyfile certfile cafile fullchain
cpanel_deploy() {
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

  _err "Not implemented yet"
  return 1

}
