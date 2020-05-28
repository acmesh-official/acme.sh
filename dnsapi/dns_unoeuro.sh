#!/usr/bin/env sh

#
#UNO_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#UNO_User="UExxxxxx"

Uno_Api="https://api.unoeuro.com/1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_unoeuro_add() {
  fulldomain=$1
  txtvalue=$2

  UNO_Key="${UNO_Key:-$(_readaccountconf_mutable UNO_Key)}"
  UNO_User="${UNO_User:-$(_readaccountconf_mutable UNO_User)}"
  if [ -z "$UNO_Key" ] || [ -z "$UNO_User" ]; then
    UNO_Key=""
    UNO_User=""
    _err "You haven't specified a UnoEuro api key and account yet."
    _err "Please create your key and try again."
    return 1
  fi

  if ! _contains "$UNO_User" "UE"; then
    _err "It seems that the UNO_User=$UNO_User is not a valid username."
    _err "Please check and retry."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable UNO_Key "$UNO_Key"
  _saveaccountconf_mutable UNO_User "$UNO_User"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _uno_rest GET "my/products/$h/dns/records"

  if ! _contains "$response" "\"status\": 200" >/dev/null; then
    _err "Error"
    return 1
  fi
  _info "Adding record"

  if _uno_rest POST "my/products/$h/dns/records" "{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"data\":\"$txtvalue\",\"ttl\":120,\"priority\":0}"; then
    if _contains "$response" "\"status\": 200" >/dev/null; then
      _info "Added, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
}

#fulldomain txtvalue
dns_unoeuro_rm() {
  fulldomain=$1
  txtvalue=$2

  UNO_Key="${UNO_Key:-$(_readaccountconf_mutable UNO_Key)}"
  UNO_User="${UNO_User:-$(_readaccountconf_mutable UNO_User)}"
  if [ -z "$UNO_Key" ] || [ -z "$UNO_User" ]; then
    UNO_Key=""
    UNO_User=""
    _err "You haven't specified a UnoEuro api key and account yet."
    _err "Please create your key and try again."
    return 1
  fi

  if ! _contains "$UNO_User" "UE"; then
    _err "It seems that the UNO_User=$UNO_User is not a valid username."
    _err "Please check and retry."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _uno_rest GET "my/products/$h/dns/records"

  if ! _contains "$response" "\"status\": 200"; then
    _err "Error"
    return 1
  fi

  if ! _contains "$response" "$_sub_domain"; then
    _info "Don't need to remove."
  else
    for record_line_number in $(echo "$response" | grep -n "$_sub_domain" | cut -d : -f 1); do
      record_line_number=$(_math "$record_line_number" - 1)
      _debug "record_line_number" "$record_line_number"
      record_id=$(echo "$response" | _head_n "$record_line_number" | _tail_n 1 1 | _egrep_o "[0-9]{1,}")
      _debug "record_id" "$record_id"

      if [ -z "$record_id" ]; then
        _err "Can not get record id to remove."
        return 1
      fi

      if ! _uno_rest DELETE "my/products/$h/dns/records/$record_id"; then
        _err "Delete record error."
        return 1
      fi
      _contains "$response" "\"status\": 200"
    done
  fi
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _uno_rest GET "my/products/$h/dns/records"; then
      return 1
    fi

    if _contains "$response" "\"status\": 200"; then
      _domain_id=$h
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_uno_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$Uno_Api/$UNO_User/$UNO_Key/$ep" "" "$m")"
  else
    response="$(_get "$Uno_Api/$UNO_User/$UNO_Key/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
