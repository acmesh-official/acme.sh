#!/usr/bin/env sh

# Here is the script to deploy the cert to G-Core CDN service (https://gcorelabs.com/ru/) using the G-Core Labs API (https://docs.gcorelabs.com/cdn/).
# Uses command line curl for send requests and jq for parse responses.
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

  _fullchain=$(awk 1 ORS='\\n' "$_cfullchain")
  _key=$(awk 1 ORS='\\n' "$_ckey")

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

  if ! [ -x "$(command -v jq)" ]; then
    _err "Please install the package jq: sudo apt-get install jq"
    return 1
  fi

  _info "Get authorization token"
  _request="{ \"username\": \"$Le_Deploy_gcore_cdn_username\", \"password\": \"$Le_Deploy_gcore_cdn_password\" }"
  _debug _request "$_request"
  _response=$(curl -s -X POST https://api.gcdn.co/auth/signin -H "Content-Type:application/json" -d "$_request")
  _debug _response "$_response"
  _token=$(echo "$_response" | jq -r '.token')
  _debug _token "$_token"

  if [ "$_token" = "null" ]; then
    _err "Error G-Core Labs API authorization"
    return 1
  fi

  _info "Find CDN resource with cname $_cdomain"
  _response=$(curl -s -X GET https://api.gcdn.co/resources -H "Authorization:Token $_token")
  _debug _response "$_response"
  _resource=$(echo "$_response" | jq -r ".[] | select(.cname == \"$_cdomain\")")
  _debug _resource "$_resource"
  _resourceId=$(echo "$_resource" | jq -r '.id')
  _sslDataOld=$(echo "$_resource" | jq -r '.sslData')
  _originGroup=$(echo "$_resource" | jq -r '.originGroup')
  _debug _resourceId "$_resourceId"
  _debug _sslDataOld "$_sslDataOld"
  _debug _originGroup "$_originGroup"

  if [ -z "$_resourceId" ] || [ "$_resourceId" = "null" ] || [ -z "$_originGroup" ] || [ "$_originGroup" = "null" ]; then
    _err "Not found CDN resource with cname $_cdomain"
    return 1
  fi

  _info "Add new SSL certificate"
  _date=$(date "+%d.%m.%Y %H:%M:%S")
  _request="{ \"name\": \"$_cdomain ($_date)\", \"sslCertificate\": \"$_fullchain\n\", \"sslPrivateKey\": \"$_key\n\" }"
  _debug _request "$_request"
  _response=$(curl -s -X POST https://api.gcdn.co/sslData -H "Content-Type:application/json" -H "Authorization:Token $_token" -d "$_request")
  _debug _response "$_response"
  _sslDataAdd=$(echo "$_response" | jq -r '.id')
  _debug _sslDataAdd "$_sslDataAdd"

  if [ "$_sslDataAdd" = "null" ]; then
    _err "Error new SSL certificate add"
    return 1
  fi

  _info "Update CDN resource"
  _request="{ \"originGroup\": $_originGroup, \"sslData\": $_sslDataAdd }"
  _debug _request "$_request"
  _response=$(curl -s -X PUT "https://api.gcdn.co/resources/$_resourceId" -H "Content-Type:application/json" -H "Authorization:Token $_token" -d "$_request")
  _debug _response "$_response"
  _sslDataNew=$(echo "$_response" | jq -r '.sslData')
  _debug _sslDataNew "$_sslDataNew"

  if [ "$_sslDataNew" != "$_sslDataAdd" ]; then
    _err "Error CDN resource update"
    return 1
  fi

  if [ -z "$_sslDataOld" ] || [ "$_sslDataOld" = "null" ]; then
    _info "Not found old SSL certificate"
  else
    _info "Delete old SSL certificate"
    _response=$(curl -s -X DELETE "https://api.gcdn.co/sslData/$_sslDataOld" -H "Authorization:Token $_token")
    _debug _response "$_response"
  fi

  _info "Certificate successfully deployed"
  return 0
}
