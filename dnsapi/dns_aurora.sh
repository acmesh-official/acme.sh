#!/usr/bin/env sh

#
#AURORA_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#AURORA_Secret="sdfsdfsdfljlbjkljlkjsdfoiwje"

AURORA_Api="https://api.auroradns.eu"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_aurora_add() {
  fulldomain=$1
  txtvalue=$2

  AURORA_Key="${AURORA_Key:-$(_readaccountconf_mutable AURORA_Key)}"
  AURORA_Secret="${AURORA_Secret:-$(_readaccountconf_mutable AURORA_Secret)}"

  if [ -z "$AURORA_Key" ] || [ -z "$AURORA_Secret" ]; then
    AURORA_Key=""
    AURORA_Secret=""
    _err "You didn't specify an Aurora api key and secret yet."
    _err "You can get yours from here https://cp.pcextreme.nl/auroradns/users."
    return 1
  fi

  #save the api key and secret to the account conf file.
  _saveaccountconf_mutable AURORA_Key "$AURORA_Key"
  _saveaccountconf_mutable AURORA_Secret "$AURORA_Secret"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if _aurora_rest POST "zones/$_domain_id/records" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"ttl\":300}"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
      return 0
    elif _contains "$response" "RecordExistsError"; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1

}

#fulldomain txtvalue
dns_aurora_rm() {
  fulldomain=$1
  txtvalue=$2

  AURORA_Key="${AURORA_Key:-$(_readaccountconf_mutable AURORA_Key)}"
  AURORA_Secret="${AURORA_Secret:-$(_readaccountconf_mutable AURORA_Secret)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting records"
  _aurora_rest GET "zones/${_domain_id}/records"

  if ! _contains "$response" "$txtvalue"; then
    _info "Don't need to remove."
  else
    records=$(echo "$response" | _normalizeJson | tr -d "[]" | sed "s/},{/}|{/g" | tr "|" "\n")
    if [ "$(echo "$records" | wc -l)" -le 2 ]; then
      _err "Can not parse records."
      return 1
    fi
    record_id=$(echo "$records" | grep "\"type\": *\"TXT\"" | grep "\"name\": *\"$_sub_domain\"" | grep "\"content\": *\"$txtvalue\"" | _egrep_o "\"id\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | _head_n 1 | tr -d " ")
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if ! _aurora_rest DELETE "zones/$_domain_id/records/$record_id"; then
      _err "Delete record error."
      return 1
    fi
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
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _aurora_rest GET "zones/$h"; then
      return 1
    fi

    if _contains "$response" "\"name\": \"$h\""; then
      _domain_id=$(echo "$response" | _normalizeJson | tr -d "{}" | tr "," "\n" | grep "\"id\": *\"" | cut -d : -f 2 | tr -d \" | _head_n 1 | tr -d " ")
      _debug _domain_id "$_domain_id"
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

_aurora_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  key_trimmed=$(echo "$AURORA_Key" | tr -d '"')
  secret_trimmed=$(echo "$AURORA_Secret" | tr -d '"')

  timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
  signature=$(printf "%s/%s%s" "$m" "$ep" "$timestamp" | _hmac sha256 "$(printf "%s" "$secret_trimmed" | _hex_dump | tr -d " ")" | _base64)
  authorization=$(printf "AuroraDNSv1 %s" "$(printf "%s:%s" "$key_trimmed" "$signature" | _base64)")

  export _H1="Content-Type: application/json; charset=UTF-8"
  export _H2="X-AuroraDNS-Date: $timestamp"
  export _H3="Authorization: $authorization"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$AURORA_Api/$ep" "" "$m")"
  else
    response="$(_get "$AURORA_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
