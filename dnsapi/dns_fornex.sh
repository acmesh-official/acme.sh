#!/usr/bin/env sh

#Author: Timur Umarov <inbox@tumarov.com>

FORNEX_API_URL="https://fornex.com/api/dns/v0.1"

########  Public functions #####################

#Usage: dns_fornex_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_fornex_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _Fornex_API; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "Unable to determine root domain"
    return 1
  else
    _debug _domain "$_domain"
  fi

  _info "Adding record"
  if _rest POST "$_domain/entry_set/add/" "host=$fulldomain&type=TXT&value=$txtvalue&apikey=$FORNEX_API_KEY"; then
    _debug _response "$response"
    if _contains "$response" '"ok": true' || _contains "$response" 'Такая запись уже существует.'; then
      _info "Added, OK"
      return 0
    fi
  fi
  _err "Add txt record error."
  return 1
}

#Usage: dns_fornex_rm   _acme-challenge.www.domain.com
dns_fornex_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _Fornex_API; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "Unable to determine root domain"
    return 1
  else
    _debug _domain "$_domain"
  fi

  _debug "Getting txt records"
  _rest GET "$_domain/entry_set.json?apikey=$FORNEX_API_KEY"

  if ! _contains "$response" "$txtvalue"; then
    _err "Txt record not found"
    return 1
  fi

  _record_id="$(echo "$response" | _egrep_o "{[^{]*\"value\"*:*\"$txtvalue\"[^}]*}" | sed -n -e 's#.*"id": \([0-9]*\).*#\1#p')"
  _debug "_record_id" "$_record_id"
  if [ -z "$_record_id" ]; then
    _err "can not find _record_id"
    return 1
  fi

  if ! _rest POST "$_domain/entry_set/$_record_id/delete/" "apikey=$FORNEX_API_KEY"; then
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
_get_root() {
  domain=$1

  i=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _rest GET "domain_list.json?q=$h&apikey=$FORNEX_API_KEY"; then
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

_Fornex_API() {
  FORNEX_API_KEY="${FORNEX_API_KEY:-$(_readaccountconf_mutable FORNEX_API_KEY)}"
  if [ -z "$FORNEX_API_KEY" ]; then
    FORNEX_API_KEY=""

    _err "You didn't specify the Fornex API key yet."
    _err "Please create your key and try again."

    return 1
  fi

  _saveaccountconf_mutable FORNEX_API_KEY "$FORNEX_API_KEY"
}

#method method action data
_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Accept: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$FORNEX_API_URL/$ep" "" "$m")"
  else
    response="$(_get "$FORNEX_API_URL/$ep" | _normalizeJson)"
  fi

  _ret="$?"
  if [ "$_ret" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
