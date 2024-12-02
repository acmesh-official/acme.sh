#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_cpanel_info='cPanel Server API
 Manage DNS via cPanel Dashboard.
Site: cPanel.net
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_cpanel
Options:
 cPanel_Username Username
 cPanel_Apitoken API Token
 cPanel_Hostname Server URL. E.g. "https://hostname:port"
Issues: github.com/acmesh-official/acme.sh/issues/3732
Author: Bjarne Saltbaek
'

########  Public functions #####################

# Used to add txt record
dns_cpanel_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Adding TXT record to cPanel based system"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _debug cPanel_Username "$cPanel_Username"
  _debug cPanel_Apitoken "$cPanel_Apitoken"
  _debug cPanel_Hostname "$cPanel_Hostname"

  if ! _cpanel_login; then
    _err "cPanel Login failed for user $cPanel_Username. Check $HTTP_HEADER file"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "No matching root domain for $fulldomain found"
    return 1
  fi
  # adding entry
  _info "Adding the entry"
  stripped_fulldomain=$(echo "$fulldomain" | sed "s/.$_domain//")
  _debug "Adding $stripped_fulldomain to $_domain zone"
  _myget "json-api/cpanel?cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=ZoneEdit&cpanel_jsonapi_func=add_zone_record&domain=$_domain&name=$stripped_fulldomain&type=TXT&txtdata=$txtvalue&ttl=1"
  if _successful_update; then return 0; fi
  _err "Couldn't create entry!"
  return 1
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_cpanel_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using cPanel based system"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _cpanel_login; then
    _err "cPanel Login failed for user $cPanel_Username. Check $HTTP_HEADER file"
    return 1
  fi

  if ! _get_root; then
    _err "No matching root domain for $fulldomain found"
    return 1
  fi

  _findentry "$fulldomain" "$txtvalue"
  if [ -z "$_id" ]; then
    _info "Entry doesn't exist, nothing to delete"
    return 0
  fi
  _debug "Deleting record..."
  _myget "json-api/cpanel?cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=ZoneEdit&cpanel_jsonapi_func=remove_zone_record&domain=$_domain&line=$_id"
  # removing entry
  _debug "_result is: $_result"

  if _successful_update; then return 0; fi
  _err "Couldn't delete entry!"
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

_get_root() {
  _myget 'json-api/cpanel?cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=ZoneEdit&cpanel_jsonapi_func=fetchzones'
  _domains=$(echo "$_result" | _egrep_o '"[a-z0-9\.\-]*":\["; cPanel first' | cut -d':' -f1 | sed 's/"//g' | sed 's/{//g')
  _debug "_result is: $_result"
  _debug "_domains is: $_domains"
  if [ -z "$_domains" ]; then
    _err "Primary domain list not found!"
    return 1
  fi
  for _domain in $_domains; do
    _debug "Checking if $fulldomain ends with $_domain"
    if (_endswith "$fulldomain" "$_domain"); then
      _debug "Root domain: $_domain"
      return 0
    fi
  done
  return 1
}

_successful_update() {
  if (echo "$_result" | _egrep_o 'data":\[[^]]*]' | grep -q '"newserial":null'); then return 1; fi
  return 0
}

_findentry() {
  _debug "In _findentry"
  #returns id of dns entry, if it exists
  _myget "json-api/cpanel?cpanel_jsonapi_apiversion=2&cpanel_jsonapi_module=ZoneEdit&cpanel_jsonapi_func=fetchzone_records&domain=$_domain"
  _id=$(echo "$_result" | sed -e "s/},{/},\n{/g" | grep "$fulldomain" | grep "$txtvalue" | _egrep_o 'line":[0-9]+' | cut -d ':' -f 2)
  _debug "_result is: $_result"
  _debug "fulldomain. is $fulldomain."
  _debug "txtvalue is $txtvalue"
  _debug "_id is: $_id"
  if [ -n "$_id" ]; then
    _debug "Entry found with _id=$_id"
    return 0
  fi
  return 1
}
