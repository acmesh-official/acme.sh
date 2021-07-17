#!/usr/bin/env sh

#
#SL_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#

SL_Api="https://api.selectel.ru/domains/v1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_selectel_add() {
  fulldomain=$1
  txtvalue=$2

  SL_Key="${SL_Key:-$(_readaccountconf_mutable SL_Key)}"

  if [ -z "$SL_Key" ]; then
    SL_Key=""
    _err "You don't specify selectel.ru api key yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key to the account conf file.
  _saveaccountconf_mutable SL_Key "$SL_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if _sl_rest POST "/$_domain_id/records/" "{\"type\": \"TXT\", \"ttl\": 60, \"name\": \"$fulldomain\", \"content\": \"$txtvalue\"}"; then
    if _contains "$response" "$txtvalue" || _contains "$response" "record_already_exists"; then
      _info "Added, OK"
      return 0
    fi
  fi
  _err "Add txt record error."
  return 1
}

#fulldomain txtvalue
dns_selectel_rm() {
  fulldomain=$1
  txtvalue=$2

  SL_Key="${SL_Key:-$(_readaccountconf_mutable SL_Key)}"

  if [ -z "$SL_Key" ]; then
    SL_Key=""
    _err "You don't specify slectel api key yet."
    _err "Please create you key and try again."
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
  _sl_rest GET "/${_domain_id}/records/"

  if ! _contains "$response" "$txtvalue"; then
    _err "Txt record not found"
    return 1
  fi

  _record_seg="$(echo "$response" | _egrep_o "\"content\" *: *\"$txtvalue\"[^}]*}")"
  _debug2 "_record_seg" "$_record_seg"
  if [ -z "$_record_seg" ]; then
    _err "can not find _record_seg"
    return 1
  fi

  _record_id="$(echo "$_record_seg" | tr "," "\n" | tr "}" "\n" | tr -d " " | grep "\"id\"" | cut -d : -f 2)"
  _debug2 "_record_id" "$_record_id"
  if [ -z "$_record_id" ]; then
    _err "can not find _record_id"
    return 1
  fi

  if ! _sl_rest DELETE "/$_domain_id/records/$_record_id"; then
    _err "Delete record error."
    return 1
  fi
  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain="$(echo "$1" | idn -u)"

  if ! _sl_rest GET "/"; then
    return 1
  fi

  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"name\": \"$h\","; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      _debug "Getting domain id for $h"
      if ! _sl_rest GET "/$(_idn "$h")"; then
        return 1
      fi
      _domain_id="$(echo "$response" | tr "," "\n" | tr "}" "\n" | tr -d " " | grep "\"id\":" | cut -d : -f 2)"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_sl_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="X-Token: $SL_Key"
  export _H2="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(printf '%b' "$(_post "$data" "$SL_Api/$ep" "" "$m")")"
  else
    response="$(printf '%b' "$(_get "$SL_Api/$ep")")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
