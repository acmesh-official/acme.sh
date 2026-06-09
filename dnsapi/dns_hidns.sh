#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_hidns_info='HiDNS
Site: github.com/hihus/hidns
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_hidns
Options:
 HIDNS_Url HiDNS instance base URL (e.g. https://hidns.example.com)
 HIDNS_Token API Token
Issues: github.com/acmesh-official/acme.sh/issues
Author: HINS
'

HIDNS_API="${HIDNS_API:-$HIDNS_Url}"

########  Public functions #####################

#Usage: dns_hidns_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_hidns_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using HiDNS API"

  if ! _hidns_init; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  body="{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"value\":\"$txtvalue\",\"ttl\":120}"

  if _hidns_rest POST "/domains/$_domain_id/records" "$body"; then
    _info "Added TXT record for $fulldomain"
    return 0
  fi

  if _contains "$response" "already exists"; then
    _info "Already exists, OK"
    return 0
  fi

  _err "Add txt record error."
  return 1
}

#Usage: dns_hidns_rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_hidns_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using HiDNS API"

  if ! _hidns_init; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting TXT records"
  if ! _hidns_rest GET "/domains/$_domain_id/records?page=1&pageSize=200&subdomain=$_sub_domain&value=$txtvalue&type=TXT"; then
    _err "Error"
    return 1
  fi

  record_id=$(echo "$response" | _egrep_o '"id":"[^"]*"' | _head_n 1 | cut -d : -f 2 | tr -d '"' | tr -d ' ')
  if [ -z "$record_id" ]; then
    record_id=$(echo "$response" | _egrep_o '"id":[0-9]*' | _head_n 1 | cut -d : -f 2 | tr -d ' ')
  fi

  _debug "record_id" "$record_id"
  if [ -z "$record_id" ]; then
    _info "Don't need to remove."
    return 0
  fi

  if ! _hidns_rest DELETE "/domains/$_domain_id/records/$record_id"; then
    _err "Delete record error."
    return 1
  fi

  _info "Deleted TXT record for $fulldomain"
  return 0
}

####################  Private functions below ##################################

_hidns_init() {
  HIDNS_Url="${HIDNS_Url:-$(_readaccountconf_mutable HIDNS_Url)}"
  HIDNS_Token="${HIDNS_Token:-$(_readaccountconf_mutable HIDNS_Token)}"

  HIDNS_Url="$(echo "$HIDNS_Url" | sed 's,/api/*$,,')"
  HIDNS_Url="$(echo "$HIDNS_Url" | sed 's,/*$,,')"

  if [ -z "$HIDNS_Url" ]; then
    HIDNS_Url=""
    _err "HIDNS_Url is not set."
    _err "Please export HIDNS_Url as the base URL of your HiDNS instance."
    return 1
  fi

  if [ -z "$HIDNS_Token" ]; then
    HIDNS_Token=""
    _err "HIDNS_Token is not set."
    _err "Please export HIDNS_Token as your HiDNS API Token."
    return 1
  fi

  _saveaccountconf_mutable HIDNS_Url "$HIDNS_Url"
  _saveaccountconf_mutable HIDNS_Token "$HIDNS_Token"

  return 0
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=123
_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(echo "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi

    if ! _hidns_rest GET "/domains?page=1&pageSize=20&keyword=$h"; then
      return 1
    fi

    _domain_pairs=$(echo "$response" | _egrep_o '"id":[0-9]*,"name":"[^"]*"')
    if [ -z "$_domain_pairs" ]; then
      _domain_pairs=$(echo "$response" | _egrep_o '"name":"[^"]*","id":[0-9]*')
    fi

    _match=$(echo "$_domain_pairs" | grep "\"name\":\"$h\"")
    if [ -n "$_match" ]; then
      _domain_id=$(echo "$_match" | _head_n 1 | _egrep_o '"id":[0-9]*' | cut -d : -f 2 | tr -d ' ')
      _sub_domain=$(echo "$domain" | cut -d . -f 1-"$p")
      _domain=$h
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_hidns_rest() {
  m=$1
  ep="$2"
  data="$3"

  export _H1="Authorization: Bearer $HIDNS_Token"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$HIDNS_Url/api$ep" "" "$m" "application/json")"
  else
    response="$(_get "$HIDNS_Url/api$ep")"
  fi

  ret="$?"

  unset _H1
  unset _H2
  unset _H3

  if [ "$ret" != "0" ]; then
    _err "error $ep"
    return 1
  fi

  _debug2 response "$response"

  http_status=$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")
  _debug2 "HTTP status" "$http_status"

  case "$http_status" in
  200 | 201 | 204) ;;
  *)
    _err "HiDNS API request failed with HTTP status $http_status"
    return 1
    ;;
  esac

  code=$(echo "$response" | _egrep_o '"code":[0-9]*' | _head_n 1 | cut -d : -f 2 | tr -d ' ')
  if [ -n "$code" ] && [ "$code" != "0" ]; then
    msg=$(echo "$response" | _egrep_o '"msg":"[^"]*"' | _head_n 1 | cut -d : -f 2 | tr -d '"')
    _err "HiDNS API error (code $code): $msg"
    return 1
  fi

  return 0
}
