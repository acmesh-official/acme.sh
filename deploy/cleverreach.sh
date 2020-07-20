#!/usr/bin/env sh
# Here is the script to deploy the cert to your CleverReach Account using the CleverReach REST API.
# Your OAuth needs the right scope, please contact CleverReach support for that.
#
# It requires that jq are in the $PATH.
#
# Written by Jan-Philipp Benecke <github@bnck.me>
# Public domain, 2017-2018
#
# Following environment variables must be set:
#
#export DEPLOY_CLEVERREACH_CLIENT_ID=myid
#export DEPLOY_CLEVERREACH_CLIENT_SECRET=mysecret

cleverreach_deploy() {
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

  _cleverreach_client_id="${DEPLOY_CLEVERREACH_CLIENT_ID}"
  _cleverreach_client_secret="${DEPLOY_CLEVERREACH_CLIENT_SECRET}"

  if [ -z "$_cleverreach_client_id" ]; then
    _err "CleverReach Client ID is not found, please define DEPLOY_CLEVERREACH_CLIENT_ID."
    return 1
  fi
  if [ -z "$_cleverreach_client_secret" ]; then
    _err "CleverReach client secret is not found, please define DEPLOY_CLEVERREACH_CLIENT_SECRET."
    return 1
  fi

  _saveaccountconf DEPLOY_CLEVERREACH_CLIENT_ID "${_cleverreach_client_id}"
  _saveaccountconf DEPLOY_CLEVERREACH_CLIENT_SECRET "${_cleverreach_client_secret}"

  _info "Obtaining a CleverReach access token"

  _data="{\"grant_type\": \"client_credentials\", \"client_id\": \"${_cleverreach_client_id}\", \"client_secret\": \"${_cleverreach_client_secret}\"}"
  _auth_result="$(_post "$_data" "https://rest.cleverreach.dev/oauth/token.php" "" "POST" "application/json")"

  _debug _data "$_data"
  _debug _auth_result "$_auth_result"

  _access_token=$(echo "$_auth_result" | _json_decode | jq -r .access_token)

  _info "Uploading certificate and key to CleverReach"

  _certData="{\"cert\":\"$(cat $_cfullchain | _json_encode)\", \"key\":\"$(cat $_ckey | _json_encode)\"}"
  export _H1="Authorization: Bearer ${_access_token}"
  _add_cert_result="$(_post "$_certData" "https://rest.cleverreach.dev/v3/ssl/${_cdomain}" "" "POST" "application/json")"

  if ! echo "$_add_cert_result" | grep '"error":' >/dev/null; then
    _info "Uploaded certificate successfully"
    return 0
  else
    _debug _add_cert_result "$_add_cert_result"
    _err "Unable to update certificate"
    return 1
  fi
}
