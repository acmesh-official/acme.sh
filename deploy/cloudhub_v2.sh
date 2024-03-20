#!/usr/bin/env sh

# Here is a script to deploy certificates to CloudHub V2 using Anypoint Platform REST APIs via curl
# A TLS Context is created and the certificates deployed on it
# (https://docs.mulesoft.com/cloudhub-2/ps-config-domains/)
#
# This script will use Connected Apps - Client Credentials
# The App must have "Cloudhub Network Administrator" or "Cloudhub Organization Admin" scope
# (https://docs.mulesoft.com/access-management/connected-apps-developers#developers)
#
# It requires following environment variables:
#
# CH2_CLIENT_ID - Connected App Client ID
# CH2_CLIENT_SECRET - Connected App Client Secret
# ORGANIZATION_ID - Anypoint Platform Organization ID
# CH2_PRIVATE_SPACE_ID - Private Space ID where the TLS Context will be created
#
#

#returns 0 means success, otherwise error.

########  Public functions #####################

#!/usr/bin/env sh

#Here is a sample custom api script.
#This file name is "myapi.sh"
#So, here must be a method   myapi_deploy()
#Which will be called by acme.sh to deploy the cert
#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
cloudhub_v2_deploy() {
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

  _getdeployconf CH2_CLIENT_ID
  _getdeployconf CH2_CLIENT_SECRET
  _getdeployconf ORGANIZATION_ID
  _getdeployconf CH2_PRIVATE_SPACE_ID

  # Validate required env vars
  if [ -z "$CH2_CLIENT_ID" ]; then
    _err "Connected App CH2_CLIENT_ID not defined."
    return 1
  fi

  if [ -z "$CH2_CLIENT_SECRET" ]; then
    _err "Connected App CH2_CLIENT_SECRET not defined."
    return 1
  fi

  if [ -z "$ORGANIZATION_ID" ]; then
    _err "ORGANIZATION_ID not defined."
    return 1
  fi

  if [ -z "$CH2_PRIVATE_SPACE_ID" ]; then
    _err "CH2_PRIVATE_SPACE_ID not defined."
    return 1
  fi

  # Set Anypoint Platform URL
  if [ -z "$ANYPOINT_URL" ]; then
    _debug "ANYPOINT_URL Not set, using default https://anypoint.mulesoft.com"
    ANYPOINT_URL="https://anypoint.mulesoft.com"
  fi

  _savedeployconf CH2_CLIENT_ID "$CH2_CLIENT_ID"
  _savedeployconf CH2_CLIENT_SECRET "$CH2_CLIENT_SECRET"
  _savedeployconf ORGANIZATION_ID "$ORGANIZATION_ID"
  _savedeployconf CH2_PRIVATE_SPACE_ID "$CH2_PRIVATE_SPACE_ID"
  _savedeployconf ANYPOINT_URL "$ANYPOINT_URL"

  # Anypoint Platform access token
  _info "Obtaining a Anypoint Platform access token"
  token_data="{\"grant_type\": \"client_credentials\", \"client_id\": \"${CH2_CLIENT_ID}\", \"client_secret\": \"${CH2_CLIENT_SECRET}\"}"
  _debug token_data "$token_data"
  token_response="$(_cloudhub_rest "POST" "/accounts/api/v2/oauth2/token" "$token_data")"
  _ret="$?"

  if [ "$_ret" != 0 ]; then
    _err "Error while creating token"
    return 1
  fi

  regex_token=".*\"access_token\":\"\([-._0-9A-Za-z]*\)\".*$"
  _debug regex_token "$regex_token"
  access_token=$(echo "$token_response" | _json_decode | sed -n "s/$regex_token/\1/p")

  _debug access_token "$access_token"
  export _H1="Authorization: Bearer ${access_token}"

  # Get TLS-Context
  tls_context_name=$(echo "$_cdomain" | tr '.' '-' | tr '*' 'x')
  tls_context_id=$(_get_tls_context_id "$tls_context_name")
  _ret="$?"

  if [ "$_ret" != 0 ]; then
    _err "Error while retrieving TLS-Context"
    return 1
  fi

  _debug tls_context_id "$tls_context_id"

  cert_data="{\"name\":\"$tls_context_name\", \"tlsConfig\": {\"keyStore\":{\"source\":\"PEM\",\"certificate\":\"$(_json_encode <"$_ccert")\", \"key\":\"$(_json_encode <"$_ckey")\", \"capath\":\"$(_json_encode <"$_cca")\"}}}"

  if [ -z "$tls_context_id" ]; then
    #Post certificate to Private Space
    _info "Creating a new TLS-Context with name: $tls_context_name"
    cert_response="$(_cloudhub_rest "POST" "/runtimefabric/api/organizations/$ORGANIZATION_ID/privatespaces/$CH2_PRIVATE_SPACE_ID/tlsContexts" "$cert_data")"
  else
    #Patch certificate to Private Space
    _info "Updating TLS-Context with name: $tls_context_name and id: $tls_context_id"
    cert_response="$(_cloudhub_rest "PATCH" "/runtimefabric/api/organizations/$ORGANIZATION_ID/privatespaces/$CH2_PRIVATE_SPACE_ID/tlsContexts/$tls_context_id" "$cert_data")"
  fi

  _ret="$?"
  _debug cert_response "$cert_response"

  if [ "$_ret" != 0 ]; then
    _err "Error while creating/updating TLS-Context"
    return 1
  fi

  _info "Certificate deployed!"
}

####################  Private functions below ##################################
# Retrieve TLS Context If from Private Space
#returns
# tls_context_id
_get_tls_context_id() {
  _domain=$1

  # Get Tls-Context
  tls_context_response="$(_cloudhub_rest "GET" "/runtimefabric/api/organizations/$ORGANIZATION_ID/privatespaces/$CH2_PRIVATE_SPACE_ID/tlsContexts" | _normalizeJson)"
  _ret="$?"

  if [ "$_ret" != 0 ]; then
    return 1
  fi

  if _contains "$tls_context_response" "\"name\":\"$_domain\"" >/dev/null; then
    tlscontext_list=$(echo "$tls_context_response" | _egrep_o "\"id\":\".*\",\"name\":\"$_domain\"")

    if [ "$tlscontext_list" ]; then
      regex_id=".*\"id\":\"\([-._0-9A-Za-z]*\)\".*$"
      tls_context_id=$(echo "$tlscontext_list" | sed -n "s/$regex_id/\1/p")
      if [ "$tls_context_id" ]; then
        _debug "TLS-Context id: $tls_context_id found! The script will update it."
        printf "%s" "$tls_context_id"
        return 0
      fi
      _err "Can't extract TLS-Context id from: $tlscontext_list"
      return 1
    fi
  fi

  return 0
}

_cloudhub_rest() {
  _method=$1
  _path="$2"
  _data="$3"

  # clear headers from previous request to avoid getting wrong http code
  : >"$HTTP_HEADER"

  _debug data "$_data"
  if [ "$_method" != "GET" ]; then
    response="$(_post "$_data" "$ANYPOINT_URL""$_path" "" "$_method" "application/json")"
  else
    response="$(_get "$ANYPOINT_URL""$_path")"
  fi
  _ret="$?"

  http_code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "HTTP status $http_code"
  _debug response "$response"

  if [ "$_ret" = "0" ] && { [ "$http_code" -ge 200 ] && [ "$http_code" -le 299 ]; }; then
    printf "%s" "$response"
    return 0
  else
    _err "Error sending request to $_path"
    _err "HTTP Status $http_code"
    _err "Response $response"
    return 1
  fi
}
