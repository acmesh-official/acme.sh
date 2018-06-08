#!/usr/bin/env sh
# Here is the script to deploy the cert to your cpanel using the cpanel API.
# Uses command line uapi.  --user option is needed only if run as root.
# Returns 0 when success.
#
# Please note that I am no longer using Github. If you want to report an issue
# or contact me, visit https://forum.webseodesigners.com/web-design-seo-and-hosting-f16/
#
# I am maintaining the urlencode function at GitLab: https://gitlab.com/santerikannisto/urlencode
#
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
  printf "%s" "$1" |
# convert newlines to audible bell so that that sed can handle the input without using non-POSIX extensions
  tr "\\r\\n" "\\a" |  
# urlencode characters
  sed -e 's/%/%25/g' -e 's/ /%20/g' -e 's/\!/%21/g' -e 's/"/%22/g' -e 's/#/%23/g' -e 's/\$/%24/g' -e 's/&/%26/g' -e 's/'\''/%27/g' -e 's/(/%28/g' -e 's/)/%29/g' -e 's/\*/%2A/g' -e 's/+/%2B/g' -e 's/,/%2C/g' -e 's/\./%2E/g' -e 's/\//%2F/g' -e 's/:/%3A/g' -e 's/;/%3B/g' -e 's/</%3C/g' -e 's/=/%3D/g' -e 's/>/%3E/g' -e 's/?/%3F/g' -e 's/@/%40/g' -e 's/\[/%5B/g' -e 's/\\/%5C/g' -e 's/\]/%5D/g' -e 's/\^/%5E/g' -e 's/_/%5F/g' -e 's/`/%60/g' -e 's/{/%7B/g' -e 's/|/%7C/g' -e 's/}/%7D/g' -e 's/~/%7E/g' -e 's/\a/%0A/g' --posix
}
