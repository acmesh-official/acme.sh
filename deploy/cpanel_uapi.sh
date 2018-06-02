#!/usr/bin/env sh
# Here is the script to deploy the cert to your cpanel using the cpanel API.
# Uses command line uapi.  --user option is needed only if run as root.
# Returns 0 when success.
# Written by Santeri Kannisto <santeri.kannisto@webseodesigners.com>
# Public domain, 2017-2018

#export DEPLOY_CPANEL_USER=myusername

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

  if ! _exists uapi; then
    _err "The command uapi is not found."
    return 1
  fi
  # read cert and key files and urlencode both
  _certstr=$(cat "$_ccert")
  _keystr=$(cat "$_ckey")
  _cert=$(_cpanel_uapi_urlencode "$_certstr")
  _key=$(_cpanel_uapi_urlencode "$_keystr")

  _debug _cert "$_cert"
  _debug _key "$_key"

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
  error_response="status: 0"
  if test "${_response#*$error_response}" != "$_response"; then
    _err "Error in deploying certificate:"
    _err "$_response"
    return 1
  fi

  _debug response "$_response"
  _info "Certificate successfully deployed"
  return 0
}

########  Private functions below #####################

_cpanel_uapi_urlencode() {
  printf "%s" "$1" | sed --posix -e 's/%/%25/g' -e ':a;N;$!ba;s/\n/%0a/g' -e 's/+/%2b/g' -e 's/[[:space:]]/%20/g' -e 's/\!/%21/g' -e 's/"/%22/g' -e 's/#/%23/g' -e 's/\$/%24/g' -e 's/&/%26/g' -e 's/'\''/%27/g' -e 's/(/%28/g' -e 's/)/%29/g' -e 's/\*/%2a/g' -e 's/,/%2c/g' -e 's/\./%2e/g' -e 's/\//%2f/g' -e 's/:/%3a/g' -e 's/;/%3b/g' -e 's/</%3c/g' -e 's/=/%3d/g' -e 's/>/%3e/g' -e 's/?/%3f/g' -e 's/@/%40/g' -e 's/\[/%5b/g' -e 's/\\/%5c/g' -e 's/\]/%5d/g' -e 's/\^/%5e/g' -e 's/_/%5f/g' -e 's/`/%60/g' -e 's/{/%7b/g' -e 's/|/%7c/g' -e 's/}/%7d/g' -e 's/~/%7e/g'
}
