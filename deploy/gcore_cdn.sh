#!/usr/bin/env sh

# Here is the script to deploy the cert to G-Core CDN service (https://gcorelabs.com/ru/) using the G-Core Labs API (https://docs.gcorelabs.com/cdn/).
# Returns 0 when success.
#
# Written by temoffey <temofffey@gmail.com>
# Public domain, 2019

#export DEPLOY_GCORE_CDN_USERNAME=myusername
#export DEPLOY_GCORE_CDN_PASSWORD=mypassword

########  Public functions #####################

#domain keyfile certfile cafile fullchain

gcore_cdn_deploy() {
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

  _fullchain=$(tr '\r\n' '*#' <"$_cfullchain" | sed 's/*#/#/g;s/##/#/g;s/#/\\n/g')
  _key=$(tr '\r\n' '*#' <"$_ckey" | sed 's/*#/#/g;s/#/\\n/g')

  _debug _fullchain "$_fullchain"
  _debug _key "$_key"

  if [ -z "$DEPLOY_GCORE_CDN_USERNAME" ]; then
    if [ -z "$Le_Deploy_gcore_cdn_username" ]; then
      _err "Please define the target username: export DEPLOY_GCORE_CDN_USERNAME=username"
      return 1
    fi
  else
    Le_Deploy_gcore_cdn_username="$DEPLOY_GCORE_CDN_USERNAME"
    _savedomainconf Le_Deploy_gcore_cdn_username "$Le_Deploy_gcore_cdn_username"
  fi

  if [ -z "$DEPLOY_GCORE_CDN_PASSWORD" ]; then
    if [ -z "$Le_Deploy_gcore_cdn_password" ]; then
      _err "Please define the target password: export DEPLOY_GCORE_CDN_PASSWORD=password"
      return 1
    fi
  else
    Le_Deploy_gcore_cdn_password="$DEPLOY_GCORE_CDN_PASSWORD"
    _savedomainconf Le_Deploy_gcore_cdn_password "$Le_Deploy_gcore_cdn_password"
  fi

  _info "Get authorization token"
  _request="{\"username\":\"$Le_Deploy_gcore_cdn_username\",\"password\":\"$Le_Deploy_gcore_cdn_password\"}"
  _debug _request "$_request"
  export _H1="Content-Type:application/json"
  _response=$(_post "$_request" "https://api.gcdn.co/auth/signin")
  _debug _response "$_response"
  _regex=".*\"token\":\"\([-._0-9A-Za-z]*\)\".*$"
  _debug _regex "$_regex"
  _token=$(echo "$_response" | sed -n "s/$_regex/\1/p")
  _debug _token "$_token"

  if [ -z "$_token" ]; then
    _err "Error G-Core Labs API authorization"
    return 1
  fi

  _info "Find CDN resource with cname $_cdomain"
  export _H2="Authorization:Token $_token"
  _response=$(_get "https://api.gcdn.co/resources")
  _debug _response "$_response"
  _regex=".*(\"id\".*?\"cname\":\"$_cdomain\".*?})"
  _regex="^.*\"cname\":\"$_cdomain\".*$"
  _debug _regex "$_regex"
  _resource=$(echo "$_response" | sed 's/},{/},\n{/g' | _egrep_o "$_regex")
  _debug _resource "$_resource"
  _regex=".*\"id\":\([0-9]*\).*\"rules\".*$"
  _debug _regex "$_regex"
  _resourceId=$(echo "$_resource" | sed -n "s/$_regex/\1/p")
  _debug _resourceId "$_resourceId"
  _regex=".*\"sslData\":\([0-9]*\).*$"
  _debug _regex "$_regex"
  _sslDataOld=$(echo "$_resource" | sed -n "s/$_regex/\1/p")
  _debug _sslDataOld "$_sslDataOld"
  _regex=".*\"originGroup\":\([0-9]*\).*$"
  _debug _regex "$_regex"
  _originGroup=$(echo "$_resource" | sed -n "s/$_regex/\1/p")
  _debug _originGroup "$_originGroup"

  if [ -z "$_resourceId" ] || [ -z "$_originGroup" ]; then
    _err "Not found CDN resource with cname $_cdomain"
    return 1
  fi

  _info "Add new SSL certificate"
  _date=$(date "+%d.%m.%Y %H:%M:%S")
  _request="{\"name\":\"$_cdomain ($_date)\",\"sslCertificate\":\"$_fullchain\",\"sslPrivateKey\":\"$_key\"}"
  _debug _request "$_request"
  _response=$(_post "$_request" "https://api.gcdn.co/sslData")
  _debug _response "$_response"
  _regex=".*\"id\":\([0-9]*\).*$"
  _debug _regex "$_regex"
  _sslDataAdd=$(echo "$_response" | sed -n "s/$_regex/\1/p")
  _debug _sslDataAdd "$_sslDataAdd"

  if [ -z "$_sslDataAdd" ]; then
    _err "Error new SSL certificate add"
    return 1
  fi

  _info "Update CDN resource"
  _request="{\"originGroup\":$_originGroup,\"sslData\":$_sslDataAdd}"
  _debug _request "$_request"
  _response=$(_post "$_request" "https://api.gcdn.co/resources/$_resourceId" '' "PUT")
  _debug _response "$_response"
  _regex=".*\"sslData\":\([0-9]*\).*$"
  _debug _regex "$_regex"
  _sslDataNew=$(echo "$_response" | sed -n "s/$_regex/\1/p")
  _debug _sslDataNew "$_sslDataNew"

  if [ "$_sslDataNew" != "$_sslDataAdd" ]; then
    _err "Error CDN resource update"
    return 1
  fi

  if [ -z "$_sslDataOld" ] || [ "$_sslDataOld" = "null" ]; then
    _info "Not found old SSL certificate"
  else
    _info "Delete old SSL certificate"
    _response=$(_post '' "https://api.gcdn.co/sslData/$_sslDataOld" '' "DELETE")
    _debug _response "$_response"
  fi

  _info "Certificate successfully deployed"
  return 0
}
