#!/usr/bin/env sh

# Script to deploy certificate to cpanel
# https://api.docs.cpanel.net/cpanel-api-2/cpanel-api-2-modules-ssl/cpanel-api-2-functions-ssl-installssl

# This deployment required following variables
# export cPanel_Username="Username"
# export cPanel_Apitoken="API Token"
# export cPanel_Hostname="Server URL. E.g. https://hostname:port"

# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
deploy_cpanel_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _info "Adding certificate to cPanel based system"
  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug cPanel_Username "$cPanel_Username"
  _debug cPanel_Apitoken "$cPanel_Apitoken"
  _debug cPanel_Hostname "$cPanel_Hostname"

  # read cert and key files and urlencode both
  _cert=$(_url_encode <"$_ccert")
  _key=$(_url_encode <"$_ckey")

  _debug2 _cert "$_cert"
  _debug2 _key "$_key"

  if ! _cpanel_login; then
    _err "cPanel Login failed for user $cPanel_Username. Check $HTTP_HEADER file"
    return 1
  fi

  # adding cert
  _info "Adding the cert"
  if ! _myget "json-api/cpanel?cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=SSL&cpanel_jsonapi_func=installssl&domain=$_cdomain&crt=$_cert&key=$_key"; then
    _err "cPanel API request failed while installing the certificate."
    return 1
  fi

  if [ -z "$_result" ]; then
    _err "cPanel API returned an empty response."
    return 1
  fi

  if ! _cpanel_result_ok; then
    return 1
  fi

  return 0
}

_cpanel_result_ok() {
  _cpanel_status="$(_egrep_o '"status"[ ]*:[ ]*[0-9]+' <<EOF
$_result
EOF
)"
  _cpanel_status="$(echo "$_cpanel_status" | sed 's/.*:[ ]*//')"

  if [ "$_cpanel_status" = "1" ]; then
    return 0
  fi

  _cpanel_error="$(_egrep_o '"statusmsg"[ ]*:[ ]*"[^"]*"' <<EOF
$_result
EOF
)"
  if [ -z "$_cpanel_error" ]; then
    _cpanel_error="$(_egrep_o '"error"[ ]*:[ ]*"[^"]*"' <<EOF
$_result
EOF
)"
  fi
  _cpanel_error="$(echo "$_cpanel_error" | sed 's/^[^:]*:[ ]*"//; s/"$//')"

  if [ -n "$_cpanel_error" ]; then
    _err "cPanel API error: $_cpanel_error"
  else
    _err "cPanel API reported failure."
  fi

  return 1
}
####################  Private functions below ##################################

_checkcredentials() {
  cPanel_Username="${cPanel_Username:-$(_readaccountconf_mutable cPanel_Username)}"
  cPanel_Apitoken="${cPanel_Apitoken:-$(_readaccountconf_mutable cPanel_Apitoken)}"
  cPanel_Hostname="${cPanel_Hostname:-$(_readaccountconf_mutable cPanel_Hostname)}"

  if [ -z "$cPanel_Username" ] || [ -z "$cPanel_Apitoken" ] || [ -z "$cPanel_Hostname" ]; then
    cPanel_Username=""
    cPanel_Apitoken=""
    cPanel_Hostname=""
    _err "You haven't specified cPanel username, apitoken and hostname yet."
    _err "Please add credentials and try again."
    return 1
  fi
  #save the credentials to the account conf file.
  _saveaccountconf_mutable cPanel_Username "$cPanel_Username"
  _saveaccountconf_mutable cPanel_Apitoken "$cPanel_Apitoken"
  _saveaccountconf_mutable cPanel_Hostname "$cPanel_Hostname"
  return 0
}

_cpanel_login() {
  if ! _checkcredentials; then return 1; fi

  if ! _myget "json-api/cpanel?cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=CustInfo&cpanel_jsonapi_func=displaycontactinfo"; then
    _err "cPanel login failed for user $cPanel_Username."
    return 1
  fi
  return 0
}

_myget() {
  #Adds auth header to request
  export _H1="Authorization: cpanel $cPanel_Username:$cPanel_Apitoken"
  _result=$(_get "$cPanel_Hostname/$1")
}

########  Private functions #####################

