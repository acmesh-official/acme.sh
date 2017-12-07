#!/usr/bin/env sh

#
#Uno_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#Uno_User="UExxxxxx"

Uno_Api="https://api.unoeuro.com/1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_unoeuro_add() {
  fulldomain=$1
  txtvalue=$2

  Uno_Key="${Uno_Key:-$(_readaccountconf_mutable Uno_Key)}"
  Uno_User="${Uno_User:-$(_readaccountconf_mutable Uno_User)}"
  if [ -z "$Uno_Key" ] || [ -z "$Uno_User" ]; then
    Uno_Key=""
    Uno_User=""
    _err "You haven't specified a UnoEuro api key and account yet."
    _err "Please create your key and try again."
    return 1
  fi

  if ! _contains "$Uno_User" "UE"; then
    _err "It seems that the Uno_User=$Uno_User is not a valid username."
    _err "Please check and retry."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable Uno_Key "$Uno_Key"
  _saveaccountconf_mutable Uno_User "$Uno_User"

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

  if ! _contains "$response" "$_sub_domain" >/dev/null; then
    _info "Adding record"

    if _uno_rest POST "my/products/$h/dns/records" "{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"data\":\"$txtvalue\",\"ttl\":120}"; then
      if _contains "$response" "\"status\": 200" >/dev/null; then
        _info "Added, OK"
        return 0
      else
        _err "Add txt record error."
        return 1
      fi
    fi
    _err "Add txt record error."
  else
    _info "Updating record"
    record_line_number=$(echo "$response" | grep -n "$_sub_domain" | cut -d : -f 1)
    record_line_number=$(($record_line_number-1))
    record_id=$(echo "$response" | _head_n "$record_line_number" | _tail_n 1 1 | _egrep_o "[0-9]{1,}")
    _debug "record_id" "$record_id"

    _uno_rest PUT "my/products/$h/dns/records/$record_id" "{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"data\":\"$txtvalue\",\"ttl\":120}"
    if _contains "$response" "\"status\": 200" >/dev/null; then
      _info "Updated, OK"
      return 0
    fi
    _err "Update error"
    return 1
  fi
}

#fulldomain txtvalue
dns_unoeuro_rm() {
  fulldomain=$1
  txtvalue=$2

  Uno_Key="${Uno_Key:-$(_readaccountconf_mutable Uno_Key)}"
  Uno_User="${Uno_User:-$(_readaccountconf_mutable Uno_User)}"
  if [ -z "$Uno_Key" ] || [ -z "$Uno_User" ]; then
    Uno_Key=""
    Uno_User=""
    _err "You haven't specified a UnoEuro api key and account yet."
    _err "Please create your key and try again."
    return 1
  fi

  if ! _contains "$Uno_User" "UE"; then
    _err "It seems that the Uno_User=$Uno_User is not a valid username."
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

  if ! _contains "$response" "\"status\": 200" >/dev/null; then
    _err "Error"
    return 1
  fi

  if ! _contains "$response" "$_sub_domain" >/dev/null; then
    _info "Don't need to remove."
  else
    record_line_number=$(echo "$response" | grep -n "$_sub_domain" | cut -d : -f 1)
    record_line_number=$(($record_line_number-1))
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

    if _contains "$response" "\"status\": 200" >/dev/null; then
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
    response="$(_post "$data" "$Uno_Api/$Uno_User/$Uno_Key/$ep" "" "$m")"
  else
    response="$(_get "$Uno_Api/$Uno_User/$Uno_Key/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
