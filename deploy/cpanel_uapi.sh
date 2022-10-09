#!/usr/bin/env sh
# Here is the script to deploy the cert to your cpanel using the cpanel API.
# Uses eiter the uapi command line or the web api depending on whether the DEPLOY_CPANEL_URL variable is defined.
# Returns 0 when success.
#
# Please note that I am no longer using Github. If you want to report an issue
# or contact me, visit https://forum.webseodesigners.com/web-design-seo-and-hosting-f16/
#
# Written by Santeri Kannisto <santeri.kannisto@webseodesigners.com>
# Public domain, 2017-2018
#
#
# When using uapi cli and running as root, please specify this mandatory variable
# export DEPLOY_CPANEL_USER=myusername
#
# When using uapi web api, please specify these mandatory variables
# export DEPLOY_CPANEL_URL=https://hostname.example.com:2083
# export DEPLOY_CPANEL_USER=myusername
# export DEPLOY_CPANEL_APITOKEN=Z5VY58Z18K2YIAXXQJCFRB447JIG9LGG
#
# Creating an api token in cpanel web ui https://docs.cpanel.net/cpanel/security/manage-api-tokens-in-cpanel/#create-an-api-token

########  Public functions #####################

#domain keyfile certfile cafile fullchain

cpanel_uapi_deploy() {
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
  _cert=$(_url_encode <"$_ccert")
  _key=$(_url_encode <"$_ckey")

  _debug _cert "$_cert"
  _debug _key "$_key"

  if [ -z "$DEPLOY_CPANEL_URL" ]; then
    _debug "Deploying using cpanel uapi cli"
    _uapi_cli_deploy
  else
    _debug "Deploying using cpanel uapi web api"
    _uapi_web_deploy
  fi

  ret=$?
  error_response="status: 0"
  if [ "$ret" != "0" -o "${_response#*$error_response}" != "$_response" ]; then
    _err "Error in deploying certificate:"
    _err "$_response"
    return $ret
  else
    _debug response "$_response"
    _info "Certificate successfully deployed"
    return $ret
  fi
}

_uapi_web_deploy() {
  if [ -z "$DEPLOY_CPANEL_USER" ]; then
    _err "Cpanel user not specified, please define the user: export DEPLOY_CPANEL_USER=username"
    return 1
  fi
  if [ -z "$DEPLOY_CPANEL_APITOKEN" ]; then
    _err "Cpanel api token not specified, please define the api token: export DEPLOY_CPANEL_APITOKEN=Z5VY58Z18K2YIAXXQJCFRB447JIG9LGG"
    return 1
  fi

  _H1="Authorization: cpanel $DEPLOY_CPANEL_USER:$DEPLOY_CPANEL_APITOKEN"
  _response=$(_get "$DEPLOY_CPANEL_URL/execute/SSL/install_ssl?domain=$_cdomain&cert=$_cert&key=$_key")
}

_uapi_cli_deploy() {
  if ! _exists uapi; then
    _err "The command uapi is not found."
    return 1
  fi
  if [ "$(id -u)" = 0 ]; then
    if [ -z "$DEPLOY_CPANEL_USER" ]; then
      _err "It seems that you are root, please define the target user name: export DEPLOY_CPANEL_USER=username"
      return 1
    fi
    _savedomainconf DEPLOY_CPANEL_USER "$DEPLOY_CPANEL_USER"
    _response=$(uapi --user="$DEPLOY_CPANEL_USER" SSL install_ssl domain="$_cdomain" cert="$_cert" key="$_key")
  else
    _response=$(uapi SSL install_ssl domain="$_cdomain" cert="$_cert" key="$_key")
  fi
}