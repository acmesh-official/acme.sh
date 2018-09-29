#!/usr/bin/env sh

Zilore_API="https://api.zilore.com/dns/v1"
# Zilore_Key="YOUR-ZILORE-API-KEY"

########  Public functions #####################

dns_zilore_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using Zilore"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  Zilore_Key="${Zilore_Key:-$(_readaccountconf_mutable Zilore_Key)}"
  if [ -z "$Zilore_Key" ]; then
    Zilore_Key=""
    _err "Please define Zilore API key"
    return 1
  fi
  _saveaccountconf_mutable Zilore_Key "$Zilore_Key"

  if ! _get_root "$fulldomain"; then
    _err "Unable to determine root domain"
    return 1
  else
    _debug _domain "$_domain"
  fi

  if _zilore_rest POST "domains/$_domain/records?record_type=TXT&record_ttl=600&record_name=$fulldomain&record_value=\"$txtvalue\""; then
    if _contains "$response" '"added"' >/dev/null; then
      _info "Added TXT record, waiting for validation"
      return 0
    else
      _debug response "$response"
      _err "Error while adding DNS records"
      return 1
    fi
  fi

  return 1
}

dns_zilore_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using Zilore"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  Zilore_Key="${Zilore_Key:-$(_readaccountconf_mutable Zilore_Key)}"
  if [ -z "$Zilore_Key" ]; then
    Zilore_Key=""
    _err "Please define Zilore API key"
    return 1
  fi
  _saveaccountconf_mutable Zilore_Key "$Zilore_Key"

  if ! _get_root "$fulldomain"; then
    _err "Unable to determine root domain"
    return 1
  else
    _debug _domain "$_domain"
  fi

  _debug "Getting TXT records"
  _zilore_rest GET "domains/${_domain}/records?search_text=$txtvalue&search_record_type=TXT"
  _debug response "$response"

  if ! _contains "$response" '"ok"' >/dev/null; then
    _err "Error while getting records list"
    return 1
  else
    _record_id=$(printf "%s\n" "$response" | _egrep_o "\"record_id\":\"[^\"]+\"" | cut -d : -f 2 | tr -d \" | _head_n 1)
    if [ -z "$_record_id" ]; then
      _err "Cannot determine _record_id"
      return 1
    else
      _debug _record_id "$_record_id"
    fi
    if ! _zilore_rest DELETE "domains/${_domain}/records?record_id=$_record_id"; then
      _err "Error while deleting chosen record"
      return 1
    fi
    _contains "$response" '"ok"'
  fi
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=2
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _zilore_rest GET "domains?search_text=$h"; then
      return 1
    fi

    if _contains "$response" "\"$h\"" >/dev/null; then
      _domain=$h
      return 0
    else
      _debug "$h not found"
    fi
    i=$(_math "$i" + 1)
  done
  return 1
}

_zilore_rest() {
  method=$1
  param=$2
  data=$3

  export _H1="X-Auth-Key: $Zilore_Key"

  if [ "$method" != "GET" ]; then
    response="$(_post "$data" "$Zilore_API/$param" "" "$method")"
  else
    response="$(_get "$Zilore_API/$param")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $param"
    return 1
  fi

  _debug2 response "$response"
  return 0
}
