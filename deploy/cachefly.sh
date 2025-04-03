#!/usr/bin/env sh

# Script to deploy certificate to CacheFly
# https://api.cachefly.com/api/2.5/docs#tag/Certificates/paths/~1certificates/post

# This deployment required following variables
# export CACHEFLY_TOKEN="Your CacheFly API Token"

# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
CACHEFLY_API_BASE="https://api.cachefly.com/api/2.5"

cachefly_deploy() {
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

  if [ -z "$CACHEFLY_TOKEN" ]; then
    _err "CACHEFLY_TOKEN is not defined."
    return 1
  else
    _savedomainconf CACHEFLY_TOKEN "$CACHEFLY_TOKEN"
  fi

  _info "Deploying certificate to CacheFly..."

  ## upload certificate
  string_fullchain=$(sed 's/$/\\n/' "$_cfullchain" | tr -d '\n')
  string_key=$(sed 's/$/\\n/' "$_ckey" | tr -d '\n')

  _request_body="{\"certificate\":\"$string_fullchain\",\"certificateKey\":\"$string_key\"}"
  _debug _request_body "$_request_body"
  _debug CACHEFLY_TOKEN "$CACHEFLY_TOKEN"
  export _H1="Authorization: Bearer $CACHEFLY_TOKEN"
  _response=$(_post "$_request_body" "$CACHEFLY_API_BASE/certificates" "" "POST" "application/json")

  if _contains "$_response" "message"; then
    _err "Error in deploying $_cdomain certificate to CacheFly."
    _err "$_response"
    return 1
  fi
  _debug response "$_response"
  _info "Domain $_cdomain certificate successfully deployed to CacheFly."
  return 0
}
