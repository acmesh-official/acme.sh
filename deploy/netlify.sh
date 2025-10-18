#!/usr/bin/env sh

# Script to deploy certificate to Netlify
# https://docs.netlify.com/api/get-started/#authentication
# https://open-api.netlify.com/#tag/sniCertificate

# This deployment required following variables
# export Netlify_ACCESS_TOKEN="Your Netlify Access Token"
# export Netlify_SITE_ID="Your Netlify Site ID"

# If have more than one SITE ID
# export Netlify_SITE_ID="SITE_ID_1 SITE_ID_2"

# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
netlify_deploy() {
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

  if [ -z "$Netlify_ACCESS_TOKEN" ]; then
    _err "Netlify_ACCESS_TOKEN is not defined."
    return 1
  else
    _savedomainconf Netlify_ACCESS_TOKEN "$Netlify_ACCESS_TOKEN"
  fi
  if [ -z "$Netlify_SITE_ID" ]; then
    _err "Netlify_SITE_ID is not defined."
    return 1
  else
    _savedomainconf Netlify_SITE_ID "$Netlify_SITE_ID"
  fi

  _info "Deploying certificate to Netlify..."

  ## upload certificate
  string_ccert=$(sed 's/$/\\n/' "$_ccert" | tr -d '\n')
  string_cca=$(sed 's/$/\\n/' "$_cca" | tr -d '\n')
  string_key=$(sed 's/$/\\n/' "$_ckey" | tr -d '\n')

  for SITE_ID in $Netlify_SITE_ID; do
    _request_body="{\"certificate\":\"$string_ccert\",\"key\":\"$string_key\",\"ca_certificates\":\"$string_cca\"}"
    _debug _request_body "$_request_body"
    _debug Netlify_ACCESS_TOKEN "$Netlify_ACCESS_TOKEN"
    export _H1="Authorization: Bearer $Netlify_ACCESS_TOKEN"
    _response=$(_post "$_request_body" "https://api.netlify.com/api/v1/sites/$SITE_ID/ssl" "" "POST" "application/json")

    if _contains "$_response" "\"error\""; then
      _err "Error in deploying $_cdomain certificate to Netlify SITE_ID $SITE_ID."
      _err "$_response"
      return 1
    fi
    _debug response "$_response"
    _info "Domain $_cdomain certificate successfully deployed to Netlify SITE_ID $SITE_ID."
  done

  return 0
}
