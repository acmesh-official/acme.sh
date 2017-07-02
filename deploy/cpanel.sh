#!/bin/bash
# Here is the script to deploy the cert to your cpanel using the cpanel API.
# Uses command line uapi. Cpanel username is needed only when run as root.
# Returns 0 when success, otherwise error.
# Written by Santeri Kannisto <santeri.kannisto@2globalnomads.info>
# Public domain, 2017

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

  # read cert and key files and urlencode both
  _certstr=`cat "$_ccert"`
  _keystr=`cat "$_ckey"`
  _cert=$(php -r "echo urlencode(\"$_certstr\");")
  _key=$(php -r "echo urlencode(\"$_keystr\");")

  _debug _cert "$_cert"
  _debug _key "$_key"

  if [[ $EUID -eq 0 ]]
  then 
    _opt="--user=$DEPLOY_CPANEL_USER SSL install_ssl"
  else
    _opt="SSL install_ssl"
  fi    

  _debug _opt "$_opt"

  response=$(uapi $_opt domain="$_cdommain" cert="$_cert" key="$_key")

  if [ $? -ne 0 ]
  then
    _err "Error in deploying certificate:"
    _err "$response"
    return 1
  fi

  _debug response "$response"
  _info "Certificate successfully deployed"
}
