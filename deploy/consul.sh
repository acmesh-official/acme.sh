#!/usr/bin/env sh

#Here is the script to deploy the cert to your consul key/value store.
#export DEPLOY_CONSUL_URL=http://localhost:8500/v1/kv
#export DEPLOY_CONSUL_ROOT_KEY=acme

########  Public functions #####################

#domain keyfile certfile cafile fullchain
consul_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  if [ -z "$DEPLOY_CONSUL_URL" ] || [ -z "$DEPLOY_CONSUL_ROOT_KEY" ]; then
    _err "You haven't specified the url or consul root key yet (DEPLOY_CONSUL_URL and DEPLOY_CONSUL_ROOT_KEY)."
    _err "Please set them via export and try again."
    _err "e.g. export DEPLOY_CONSUL_URL=http://localhost:8500/v1/kv"
    _err "e.g. export DEPLOY_CONSUL_ROOT_KEY=acme"
    return 1
  fi

  #Save consul url if it's succesful (First run case)
  _saveaccountconf DEPLOY_CONSUL_URL "$DEPLOY_CONSUL_URL"
  _saveaccountconf DEPLOY_CONSUL_ROOT_KEY "$DEPLOY_CONSUL_ROOT_KEY"

  _info "Deploying certificate to consul Key/Value store"
  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug DEPLOY_CONSUL_URL "$DEPLOY_CONSUL_URL"
  _debug DEPLOY_CONSUL_ROOT_KEY "$DEPLOY_CONSUL_ROOT_KEY"
  
  # set base url for all uploads
  upload_base_url="${DEPLOY_CONSUL_URL}/${DEPLOY_CONSUL_ROOT_KEY}/${_cdomain}"
  _debug upload_base_url "$upload_base_url"

  # private
  _info uploading "$_ckey"
  response=$(_post "@${_ckey}" "${upload_base_url}/${_cdomain}.key" "" "PUT")
  _debugw response "$response"

  # public
  _info uploading "$_ccert"
  response=$(_post "@${_ccert}" "${upload_base_url}/${_cdomain}.cer" "" "PUT")
  _debugw response "$response"

  # ca
  _info uploading "$_cca"
  response=$(_post "@${_cca}" "${upload_base_url}/ca.cer" "" "PUT")
  _debugw response "$response"

  # fullchain
  _info uploading "$_cfullchain"
  response=$(_post "@${_cfullchain}" "${upload_base_url}/fullchain.cer" "" "PUT")
  _debugw response "$response"

  return 0

}

####################  Private functions below ##################################
