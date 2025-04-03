#!/usr/bin/env sh

# Here is a script to deploy cert to edgio using its API
# https://docs.edg.io/guides/v7/develop/rest_api/authentication
# https://docs.edg.io/rest_api/#tag/tls-certs/operation/postConfigV01TlsCerts

# This deployment required following variables
# export EDGIO_CLIENT_ID="Your Edgio Client ID"
# export EDGIO_CLIENT_SECRET="Your Edgio Client Secret"
# export EDGIO_ENVIRONMENT_ID="Your Edgio Environment ID"

# If have more than one Environment ID
# export EDGIO_ENVIRONMENT_ID="ENVIRONMENT_ID_1 ENVIRONMENT_ID_2"

# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
edgio_deploy() {
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

  if [ -z "$EDGIO_CLIENT_ID" ]; then
    _err "EDGIO_CLIENT_ID is not defined."
    return 1
  else
    _savedomainconf EDGIO_CLIENT_ID "$EDGIO_CLIENT_ID"
  fi

  if [ -z "$EDGIO_CLIENT_SECRET" ]; then
    _err "EDGIO_CLIENT_SECRET is not defined."
    return 1
  else
    _savedomainconf EDGIO_CLIENT_SECRET "$EDGIO_CLIENT_SECRET"
  fi

  if [ -z "$EDGIO_ENVIRONMENT_ID" ]; then
    _err "EDGIO_ENVIRONMENT_ID is not defined."
    return 1
  else
    _savedomainconf EDGIO_ENVIRONMENT_ID "$EDGIO_ENVIRONMENT_ID"
  fi

  _info "Getting access token"
  _data="client_id=$EDGIO_CLIENT_ID&client_secret=$EDGIO_CLIENT_SECRET&grant_type=client_credentials&scope=app.config"
  _debug Get_access_token_data "$_data"
  _response=$(_post "$_data" "https://id.edgio.app/connect/token" "" "POST" "application/x-www-form-urlencoded")
  _debug Get_access_token_response "$_response"
  _access_token=$(echo "$_response" | _json_decode | _egrep_o '"access_token":"[^"]*' | cut -d : -f 2 | tr -d '"')
  _debug _access_token "$_access_token"
  if [ -z "$_access_token" ]; then
    _err "Error in getting access token"
    return 1
  fi

  _info "Uploading certificate"
  string_ccert=$(sed 's/$/\\n/' "$_ccert" | tr -d '\n')
  string_cca=$(sed 's/$/\\n/' "$_cca" | tr -d '\n')
  string_key=$(sed 's/$/\\n/' "$_ckey" | tr -d '\n')

  for ENVIRONMENT_ID in $EDGIO_ENVIRONMENT_ID; do
    _data="{\"environment_id\":\"$ENVIRONMENT_ID\",\"primary_cert\":\"$string_ccert\",\"intermediate_cert\":\"$string_cca\",\"private_key\":\"$string_key\"}"
    _debug Upload_certificate_data "$_data"
    _H1="Authorization: Bearer $_access_token"
    _response=$(_post "$_data" "https://edgioapis.com/config/v0.1/tls-certs" "" "POST" "application/json")
    if _contains "$_response" "message"; then
      _err "Error in deploying $_cdomain certificate to Edgio ENVIRONMENT_ID $ENVIRONMENT_ID."
      _err "$_response"
      return 1
    fi
    _debug Upload_certificate_response "$_response"
    _info "Domain $_cdomain certificate successfully deployed to Edgio ENVIRONMENT_ID $ENVIRONMENT_ID."
  done

  return 0
}
