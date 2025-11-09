#!/usr/bin/env sh

# Script to deploy certificate to DirectAdmin
# https://docs.directadmin.com/directadmin/customizing-workflow/api-all-about.html#creating-a-login-key
# https://docs.directadmin.com/changelog/version-1.24.4.html#cmd-api-catch-all-pop-passwords-frontpage-protected-dirs-ssl-certs

# This deployment required following variables
# export DirectAdmin_SCHEME="https" # Optional, https or http, defaults to https
# export DirectAdmin_ENDPOINT="example.com:2222"
# export DirectAdmin_USERNAME="Your DirectAdmin Username"
# export DirectAdmin_KEY="Your DirectAdmin Login Key or Password"
# export DirectAdmin_MAIN_DOMAIN="Your DirectAdmin Main Domain, NOT Subdomain"

# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
directadmin_deploy() {
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

  if [ -z "$DirectAdmin_ENDPOINT" ]; then
    _err "DirectAdmin_ENDPOINT is not defined."
    return 1
  else
    _savedomainconf DirectAdmin_ENDPOINT "$DirectAdmin_ENDPOINT"
  fi
  if [ -z "$DirectAdmin_USERNAME" ]; then
    _err "DirectAdmin_USERNAME is not defined."
    return 1
  else
    _savedomainconf DirectAdmin_USERNAME "$DirectAdmin_USERNAME"
  fi
  if [ -z "$DirectAdmin_KEY" ]; then
    _err "DirectAdmin_KEY is not defined."
    return 1
  else
    _savedomainconf DirectAdmin_KEY "$DirectAdmin_KEY"
  fi
  if [ -z "$DirectAdmin_MAIN_DOMAIN" ]; then
    _err "DirectAdmin_MAIN_DOMAIN is not defined."
    return 1
  else
    _savedomainconf DirectAdmin_MAIN_DOMAIN "$DirectAdmin_MAIN_DOMAIN"
  fi

  # Optional SCHEME
  _getdeployconf DirectAdmin_SCHEME
  # set default values for DirectAdmin_SCHEME
  [ -n "${DirectAdmin_SCHEME}" ] || DirectAdmin_SCHEME="https"

  _info "Deploying certificate to DirectAdmin..."

  # upload certificate
  string_cfullchain=$(sed 's/$/\\n/' "$_cfullchain" | tr -d '\n')
  string_key=$(sed 's/$/\\n/' "$_ckey" | tr -d '\n')

  _request_body="{\"domain\":\"$DirectAdmin_MAIN_DOMAIN\",\"action\":\"save\",\"type\":\"paste\",\"certificate\":\"$string_key\n$string_cfullchain\n\"}"
  _debug _request_body "$_request_body"
  _debug DirectAdmin_ENDPOINT "$DirectAdmin_ENDPOINT"
  _debug DirectAdmin_USERNAME "$DirectAdmin_USERNAME"
  _debug DirectAdmin_KEY "$DirectAdmin_KEY"
  _debug DirectAdmin_MAIN_DOMAIN "$DirectAdmin_MAIN_DOMAIN"
  _response=$(_post "$_request_body" "$DirectAdmin_SCHEME://$DirectAdmin_USERNAME:$DirectAdmin_KEY@$DirectAdmin_ENDPOINT/CMD_API_SSL" "" "POST" "application/json")

  if _contains "$_response" "error=1"; then
    _err "Error in deploying $_cdomain certificate to DirectAdmin Domain $DirectAdmin_MAIN_DOMAIN."
    _err "$_response"
    return 1
  fi

  _info "$_response"
  _info "Domain $_cdomain certificate successfully deployed to DirectAdmin Domain $DirectAdmin_MAIN_DOMAIN."

  return 0
}
