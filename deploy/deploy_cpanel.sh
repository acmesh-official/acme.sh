#!/usr/bin/env sh

# Script to deploy certificate to cpanel
# https://api.docs.cpanel.net/cpanel-api-2/cpanel-api-2-modules-ssl/cpanel-api-2-functions-ssl-installssl

# This deployment required following variables
# export Netlify_ACCESS_TOKEN="Your Netlify Access Token"
# export Netlify_SITE_ID="Your Netlify Site ID"

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
  _myget "json-api/cpanel?cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=SSL&cpanel_jsonapi_func=installssl&domain=$_domain&crt=$_cert&key=$_key"
  # if _successful_update; then return 0; fi
  # _err "Couldn't create entry!"
  # return 1
  return 0
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

# Internal utility to process YML from UAPI - looks at main_domain, sub_domains, addon domains and parked domains
#[response]
__cpanel_parse_response() {
  if [ $# -gt 0 ]; then resp="$*"; else resp="$(cat)"; fi

  echo "$resp" |
    sed -En \
      -e 's/\r$//' \
      -e 's/^( *)([_.[:alnum:]]+) *: *(.*)/\1,\2,\3/p' \
      -e 's/^( *)- (.*)/\1,-,\2/p' |
    awk -F, '{
      level = length($1)/2;
      section[level] = $2;
      for (i in section) {if (i > level) {delete section[i]}}
      if (length($3) > 0) {
        prefix="";
        for (i=0; i < level; i++)
          { prefix = (prefix)(section[i])("/") }
        printf("%s%s=%s\n", prefix, $2, $3);
      }
    }' |
    sed -En -e 's/^result\/data\/(main_domain|sub_domains\/-|addon_domains\/-|parked_domains\/-)=(.*)$/\2/p'
}

# Load parameter by prefix+name - fallback to default if not set, and save to config
#pname pdefault
__cpanel_initautoparam() {
  pname="$1"
  pdefault="$2"
  pkey="DEPLOY_CPANEL_AUTO_$pname"

  _getdeployconf "$pkey"
  [ -n "$(eval echo "\"\$$pkey\"")" ] || eval "$pkey=\"$pdefault\""
  _debug2 "$pkey" "$(eval echo "\"\$$pkey\"")"
  _savedeployconf "$pkey" "$(eval echo "\"\$$pkey\"")"
}
