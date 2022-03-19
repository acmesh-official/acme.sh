#!/usr/bin/env sh
# Here is the script to deploy the cert to your CleverReach Account using the CleverReach REST API.
# Your OAuth needs the right scope, please contact CleverReach support for that.
#
# Written by Jan-Philipp Benecke <github@bnck.me>
# Public domain, 2020
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

  _rest_endpoint="https://rest.cleverreach.com"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  _getdeployconf DEPLOY_CLEVERREACH_CLIENT_ID
  _getdeployconf DEPLOY_CLEVERREACH_CLIENT_SECRET
  _getdeployconf DEPLOY_CLEVERREACH_SUBCLIENT_ID

  if [ -z "${DEPLOY_CLEVERREACH_CLIENT_ID}" ]; then
    _err "CleverReach Client ID is not found, please define DEPLOY_CLEVERREACH_CLIENT_ID."
    return 1
  fi
  if [ -z "${DEPLOY_CLEVERREACH_CLIENT_SECRET}" ]; then
    _err "CleverReach client secret is not found, please define DEPLOY_CLEVERREACH_CLIENT_SECRET."
    return 1
  fi

  _savedeployconf DEPLOY_CLEVERREACH_CLIENT_ID "${DEPLOY_CLEVERREACH_CLIENT_ID}"
  _savedeployconf DEPLOY_CLEVERREACH_CLIENT_SECRET "${DEPLOY_CLEVERREACH_CLIENT_SECRET}"
  _savedeployconf DEPLOY_CLEVERREACH_SUBCLIENT_ID "${DEPLOY_CLEVERREACH_SUBCLIENT_ID}"

  _info "Obtaining a CleverReach access token"

  _data="{\"grant_type\": \"client_credentials\", \"client_id\": \"${DEPLOY_CLEVERREACH_CLIENT_ID}\", \"client_secret\": \"${DEPLOY_CLEVERREACH_CLIENT_SECRET}\"}"
  _auth_result="$(_post "$_data" "$_rest_endpoint/oauth/token.php" "" "POST" "application/json")"

  _debug _data "$_data"
  _debug _auth_result "$_auth_result"

  _regex=".*\"access_token\":\"\([-._0-9A-Za-z]*\)\".*$"
  _debug _regex "$_regex"
  _access_token=$(echo "$_auth_result" | _json_decode | sed -n "s/$_regex/\1/p")

  _debug _subclient "${DEPLOY_CLEVERREACH_SUBCLIENT_ID}"

  if [ -n "${DEPLOY_CLEVERREACH_SUBCLIENT_ID}" ]; then
    _info "Obtaining token for sub-client ${DEPLOY_CLEVERREACH_SUBCLIENT_ID}"
    export _H1="Authorization: Bearer ${_access_token}"
    _subclient_token_result="$(_get "$_rest_endpoint/v3/clients/$DEPLOY_CLEVERREACH_SUBCLIENT_ID/token")"
    _access_token=$(echo "$_subclient_token_result" | sed -n "s/\"//p")

    _debug _subclient_token_result "$_access_token"

    _info "Destroying parent token at CleverReach, as it not needed anymore"
    _destroy_result="$(_post "" "$_rest_endpoint/v3/oauth/token.json" "" "DELETE" "application/json")"
    _debug _destroy_result "$_destroy_result"
  fi

  _info "Uploading certificate and key to CleverReach"

  _certData="{\"cert\":\"$(_json_encode <"$_cfullchain")\", \"key\":\"$(_json_encode <"$_ckey")\"}"
  export _H1="Authorization: Bearer ${_access_token}"
  _add_cert_result="$(_post "$_certData" "$_rest_endpoint/v3/ssl" "" "POST" "application/json")"

  if [ -z "${DEPLOY_CLEVERREACH_SUBCLIENT_ID}" ]; then
    _info "Destroying token at CleverReach, as it not needed anymore"
    _destroy_result="$(_post "" "$_rest_endpoint/v3/oauth/token.json" "" "DELETE" "application/json")"
    _debug _destroy_result "$_destroy_result"
  fi

  if ! echo "$_add_cert_result" | grep '"error":' >/dev/null; then
    _info "Uploaded certificate successfully"
    return 0
  else
    _debug _add_cert_result "$_add_cert_result"
    _err "Unable to update certificate"
    return 1
  fi
}
