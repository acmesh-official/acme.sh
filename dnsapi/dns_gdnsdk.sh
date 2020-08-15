#!/usr/bin/env sh
#Author: Herman Sletteng
#Report Bugs here: https://github.com/loial/acme.sh
#
#
# Note, gratisdns requires a login first, so the script needs to handle
# temporary cookies. Since acme.sh _get/_post currently don't directly support
# cookies, I've defined wrapper functions _myget/_mypost to set the headers

GDNSDK_API="https://admin.gratisdns.com"
########  Public functions #####################
#Usage: dns_gdnsdk_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_gdnsdk_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using gratisdns.dk"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  if ! _gratisdns_login; then
    _err "Login failed!"
    return 1
  fi
  #finding domain zone
  if ! _get_domain; then
    _err "No matching root domain for $fulldomain found"
    return 1
  fi
  # adding entry
  _info "Adding the entry"
  _mypost "action=dns_primary_record_added_txt&user_domain=$_domain&name=$fulldomain&txtdata=$txtvalue&ttl=1"
  if _successful_update; then return 0; fi
  _err "Couldn't create entry!"
  return 1
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_gdnsdk_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using gratisdns.dk"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  if ! _gratisdns_login; then
    _err "Login failed!"
    return 1
  fi
  if ! _get_domain; then
    _err "No matching root domain for $fulldomain found"
    return 1
  fi
  _findentry "$fulldomain" "$txtvalue"
  if [ -z "$_id" ]; then
    _info "Entry doesn't exist, nothing to delete"
    return 0
  fi
  _debug "Deleting record..."
  _mypost "action=dns_primary_delete_txt&user_domain=$_domain&id=$_id"
  # removing entry

  if _successful_update; then return 0; fi
  _err "Couldn't delete entry!"
  return 1
}

####################  Private functions below ##################################

_checkcredentials() {
  GDNSDK_Username="${GDNSDK_Username:-$(_readaccountconf_mutable GDNSDK_Username)}"
  GDNSDK_Password="${GDNSDK_Password:-$(_readaccountconf_mutable GDNSDK_Password)}"

  if [ -z "$GDNSDK_Username" ] || [ -z "$GDNSDK_Password" ]; then
    GDNSDK_Username=""
    GDNSDK_Password=""
    _err "You haven't specified gratisdns.dk username and password yet."
    _err "Please add credentials and try again."
    return 1
  fi
  #save the credentials to the account conf file.
  _saveaccountconf_mutable GDNSDK_Username "$GDNSDK_Username"
  _saveaccountconf_mutable GDNSDK_Password "$GDNSDK_Password"
  return 0
}

_checkcookie() {
  GDNSDK_Cookie="${GDNSDK_Cookie:-$(_readaccountconf_mutable GDNSDK_Cookie)}"
  if [ -z "$GDNSDK_Cookie" ]; then
    _debug "No cached cookie found"
    return 1
  fi
  _myget "action="
  if (echo "$_result" | grep -q "logmeout"); then
    _debug "Cached cookie still valid"
    return 0
  fi
  _debug "Cached cookie no longer valid"
  GDNSDK_Cookie=""
  _saveaccountconf_mutable GDNSDK_Cookie "$GDNSDK_Cookie"
  return 1
}

_gratisdns_login() {
  if ! _checkcredentials; then return 1; fi

  if _checkcookie; then
    _debug "Already logged in"
    return 0
  fi
  _debug "Logging into GratisDNS with user $GDNSDK_Username"

  if ! _mypost "login=$GDNSDK_Username&password=$GDNSDK_Password&action=logmein"; then
    _err "GratisDNS login failed for user $GDNSDK_Username bad RC from _post"
    return 1
  fi

  GDNSDK_Cookie="$(grep -A 15 '302 Found' "$HTTP_HEADER" | _egrep_o 'Cookie: [^;]*' | _head_n 1 | cut -d ' ' -f2)"

  if [ -z "$GDNSDK_Cookie" ]; then
    _err "GratisDNS login failed for user $GDNSDK_Username. Check $HTTP_HEADER file"
    return 1
  fi
  export GDNSDK_Cookie
  _saveaccountconf_mutable GDNSDK_Cookie "$GDNSDK_Cookie"
  return 0
}

_myget() {
  #Adds cookie to request
  export _H1="Cookie: $GDNSDK_Cookie"
  _result=$(_get "$GDNSDK_API?$1")
}
_mypost() {
  #Adds cookie to request
  export _H1="Cookie: $GDNSDK_Cookie"
  _result=$(_post "$1" "$GDNSDK_API")
}

_get_domain() {
  _myget 'action=dns_primarydns'
  _domains=$(echo "$_result" | _egrep_o ' domain="[[:alnum:]._-]+' | sed 's/^.*"//')
  if [ -z "$_domains" ]; then
    _err "Primary domain list not found!"
    return 1
  fi
  for _domain in $_domains; do
    if (_endswith "$fulldomain" "$_domain"); then
      _debug "Root domain: $_domain"
      return 0
    fi
  done
  return 1
}

_successful_update() {
  if (echo "$_result" | grep -q 'table-success'); then return 0; fi
  return 1
}

_findentry() {
  #args    $1: fulldomain, $2: txtvalue
  #returns id of dns entry, if it exists
  _myget "action=dns_primary_changeDNSsetup&user_domain=$_domain"
  _debug3 "_result: $_result"

  _tmp_result=$(echo "$_result" | tr -d '\n\r' | _egrep_o "<td>$1</td>\s*<td>$2</td>[^?]*[^&]*&id=[^&]*")
  _debug _tmp_result "$_tmp_result"
  if [ -z "${_tmp_result:-}" ]; then
    _debug "The variable is _tmp_result is not supposed to be empty, there may be something wrong with the script"
  fi

  _id=$(echo "$_tmp_result" | sed 's/^.*=//')
  if [ -n "$_id" ]; then
    _debug "Entry found with _id=$_id"
    return 0
  fi
  return 1
}
