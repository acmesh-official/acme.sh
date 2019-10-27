#!/usr/bin/env sh

#Author: Rolph Haspers <r.haspers@global.leaseweb.com>
#Utilize leaseweb.com API to finish dns-01 verifications.
#Requires a Leaseweb API Key (export LSW_Key="Your Key")
#See http://developer.leaseweb.com for more information.
########  Public functions #####################

LSW_API="https://api.leaseweb.com/hosting/v2/domains/"

#Usage: dns_leaseweb_add   _acme-challenge.www.domain.com
dns_leaseweb_add() {
  fulldomain=$1
  txtvalue=$2

  LSW_Key="${LSW_Key:-$(_readaccountconf_mutable LSW_Key)}"
  if [ -z "$LSW_Key" ]; then
    LSW_Key=""
    _err "You don't specify Leaseweb api key yet."
    _err "Please create your key and try again."
    return 1
  fi

  #save the api key to the account conf file.
  _saveaccountconf_mutable LSW_Key "$LSW_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _root_domain "$_domain"
  _debug _domain "$fulldomain"

  if _lsw_api "POST" "$_domain" "$fulldomain" "$txtvalue"; then
    if [ "$_code" = "201" ]; then
      _info "Added, OK"
      return 0
    else
      _err "Add txt record error, invalid code. Code: $_code"
      return 1
    fi
  fi
  _err "Add txt record error."

  return 1
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_leaseweb_rm() {
  fulldomain=$1
  txtvalue=$2

  LSW_Key="${LSW_Key:-$(_readaccountconf_mutable LSW_Key)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _root_domain "$_domain"
  _debug _domain "$fulldomain"

  if _lsw_api "DELETE" "$_domain" "$fulldomain" "$txtvalue"; then
    if [ "$_code" = "204" ]; then
      _info "Deleted, OK"
      return 0
    else
      _err "Delete txt record error."
      return 1
    fi
  fi
  _err "Delete txt record error."

  return 1
}

####################  Private functions below ##################################
# _acme-challenge.www.domain.com
# returns
# _domain=domain.com
_get_root() {
  rdomain=$1
  i="$(echo "$rdomain" | tr '.' ' ' | wc -w)"
  i=$(_math "$i" - 1)

  while true; do
    h=$(printf "%s" "$rdomain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1 #not valid domain
    fi

    #Check API if domain exists
    if _lsw_api "GET" "$h"; then
      if [ "$_code" = "200" ]; then
        _domain="$h"
        return 0
      fi
    fi
    i=$(_math "$i" - 1)
    if [ "$i" -lt 2 ]; then
      return 1 #not found, no need to check _acme-challenge.sub.domain in leaseweb api.
    fi
  done

  return 1
}

_lsw_api() {
  cmd=$1
  d=$2
  fd=$3
  tvalue=$4

  # Construct the HTTP Authorization header
  export _H2="Content-Type: application/json"
  export _H1="X-Lsw-Auth: ${LSW_Key}"

  if [ "$cmd" = "GET" ]; then
    response="$(_get "$LSW_API/$d")"
    _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
    _debug "http response code $_code"
    _debug response "$response"
    return 0
  fi

  if [ "$cmd" = "POST" ]; then
    data="{\"name\": \"$fd.\",\"type\": \"TXT\",\"content\": [\"$tvalue\"],\"ttl\": 60}"
    response="$(_post "$data" "$LSW_API/$d/resourceRecordSets" "$data" "POST")"
    _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
    _debug "http response code $_code"
    _debug response "$response"
    return 0
  fi

  if [ "$cmd" = "DELETE" ]; then
    response="$(_post "" "$LSW_API/$d/resourceRecordSets/$fd/TXT" "" "DELETE")"
    _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
    _debug "http response code $_code"
    _debug response "$response"
    return 0
  fi

  return 1
}
