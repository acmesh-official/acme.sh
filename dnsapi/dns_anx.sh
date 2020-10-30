#!/usr/bin/env sh

# Anexia CloudDNS acme.sh hook
# Author: MA

#ANX_Token="xxxx"

ANX_API='https://engine.anexia-it.com/api/clouddns/v1'

########  Public functions #####################

dns_anx_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using ANX CDNS API"

  ANX_Token="${ANX_Token:-$(_readaccountconf_mutable ANX_Token)}"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if [ "$ANX_Token" ]; then
    _saveaccountconf_mutable ANX_Token "$ANX_Token"
  else
    _err "You didn't specify a ANEXIA Engine API token."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  # Always add records, wildcard need two records with the same name
  _anx_rest POST "zone.json/${_domain}/records" "{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"rdata\":\"$txtvalue\"}"
  if _contains "$response" "$txtvalue"; then
    return 0
  else
    return 1
  fi
}

dns_anx_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using ANX CDNS API"

  ANX_Token="${ANX_Token:-$(_readaccountconf_mutable ANX_Token)}"

  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _get_record_id

  if _is_uuid "$_record_id"; then
    if ! _anx_rest DELETE "zone.json/${_domain}/records/$_record_id"; then
      _err "Delete record"
      return 1
    fi
  else
    _info "No record found."
  fi
  echo "$response" | tr -d " " | grep \"status\":\"OK\" >/dev/null
}

####################  Private functions below ##################################

_is_uuid() {
  pattern='^\{?[A-Z0-9a-z]{8}-[A-Z0-9a-z]{4}-[A-Z0-9a-z]{4}-[A-Z0-9a-z]{4}-[A-Z0-9a-z]{12}\}?$'
  if echo "$1" | _egrep_o "$pattern" >/dev/null; then
    return 0
  fi
  return 1
}

_get_record_id() {
  _debug subdomain "$_sub_domain"
  _debug domain "$_domain"

  if _anx_rest GET "zone.json/${_domain}/records?name=$_sub_domain&type=TXT"; then
    _debug response "$response"
    if _contains "$response" "\"name\":\"$_sub_domain\"" >/dev/null; then
      _record_id=$(printf "%s\n" "$response" | _egrep_o "\[.\"identifier\":\"[^\"]*\"" | head -n 1 | cut -d : -f 2 | tr -d \")
    else
      _record_id=''
    fi
  else
    _err "Search existing record"
  fi
}

_anx_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Token $ANX_Token"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "${ANX_API}/$ep" "" "$m")"
  else
    response="$(_get "${ANX_API}/$ep")"
  fi

  # shellcheck disable=SC2181
  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug response "$response"
  return 0
}

_get_root() {
  domain=$1
  i=1
  p=1

  _anx_rest GET "zone.json"

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}
