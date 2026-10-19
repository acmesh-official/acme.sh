#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_connbyte_info='ConnByte
Site: connbyte.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_connbyte
Options:
 CONNBYTE_Token API Token. Create it in the ConnByte customer panel, see https://connbyte.com/
 CONNBYTE_TTL TTL of the TXT record in seconds. Optional. Default "120".
Issues: github.com/acmesh-official/acme.sh/issues/7342
Author: ConnByte <team@connbyte.com>
'

CONNBYTE_Api="https://api.connbyte.com"

########  Public functions #####################

# Usage: dns_connbyte_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_connbyte_add() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue="$2"

  if ! _connbyte_init; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain: $fulldomain"
    return 1
  fi
  _debug _zone_id "$_zone_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding TXT record for $fulldomain"
  data="{\"zoneId\":\"$_zone_id\",\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"ttl\":$CONNBYTE_TTL,\"priority\":0,\"disabled\":false}"
  if ! _connbyte_rest "ns/record/create" "$data"; then
    _err "Could not add TXT record for $fulldomain"
    return 1
  fi
  _info "TXT record added"
  return 0
}

# Usage: dns_connbyte_rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_connbyte_rm() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue="$2"

  if ! _connbyte_init; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "invalid domain: $fulldomain"
    return 1
  fi
  _debug _zone_id "$_zone_id"
  _debug _sub_domain "$_sub_domain"

  if ! _connbyte_rest "ns/record/list" "{\"zoneId\":\"$_zone_id\"}"; then
    _err "Could not list records of zone $_domain"
    return 1
  fi

  # Each record is an innermost JSON object, e.g. (TXT content may be stored quoted)
  # {"id":435,"name":"_acme-challenge.example.com","type":"TXT","content":"...","ttl":120,"priority":0,"disabled":0}
  record_ids="$(echo "$response" | tr -d '\n\r' | _egrep_o '\{[^{}]*\}' |
    grep "\"type\" *: *\"TXT\"" |
    grep "\"name\" *: *\"$fulldomain\"" |
    grep -F "$txtvalue" |
    _egrep_o "\"id\" *: *[0-9]+" | _egrep_o "[0-9]+")"
  _debug record_ids "$record_ids"

  if [ -z "$record_ids" ]; then
    _info "TXT record not found, nothing to remove"
    return 0
  fi

  for record_id in $record_ids; do
    _info "Removing TXT record $record_id"
    if ! _connbyte_rest "ns/record/delete" "{\"zoneId\":\"$_zone_id\",\"recordId\":$record_id}"; then
      _err "Could not remove TXT record $record_id"
      return 1
    fi
  done
  return 0
}

####################  Private functions below ##################################

_connbyte_init() {
  CONNBYTE_Token="${CONNBYTE_Token:-$(_readaccountconf_mutable CONNBYTE_Token)}"
  CONNBYTE_TTL="${CONNBYTE_TTL:-$(_readaccountconf_mutable CONNBYTE_TTL)}"

  if [ -z "$CONNBYTE_Token" ]; then
    CONNBYTE_Token=""
    _err "You did not specify the ConnByte API token."
    _err "Please export CONNBYTE_Token and try again."
    return 1
  fi

  if [ -z "$CONNBYTE_TTL" ]; then
    CONNBYTE_TTL=120
  fi
  case "$CONNBYTE_TTL" in
  '' | *[!0-9]*)
    _err "CONNBYTE_TTL must be a number"
    return 1
    ;;
  esac

  _saveaccountconf_mutable CONNBYTE_Token "$CONNBYTE_Token"
  if [ "$CONNBYTE_TTL" != "120" ]; then
    _saveaccountconf_mutable CONNBYTE_TTL "$CONNBYTE_TTL"
  fi
  return 0
}

# _acme-challenge.www.domain.com
# returns
#  _sub_domain=_acme-challenge.www
#  _domain=domain.com
#  _zone_id=01DXF6DT00ZZZHQPP3JFJS8VEE
_get_root() {
  domain=$1

  if ! _connbyte_rest "ns/zone/list" "{}"; then
    return 1
  fi
  zones="$response"

  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      # not valid
      return 1
    fi

    zone_id="$(echo "$zones" | tr -d '\n\r' | _egrep_o '\{[^{}]*\}' |
      grep "\"zone\" *: *\"$h\"" | _head_n 1 |
      _egrep_o "\"id\" *: *\"[0-9A-Za-z]+\"" | cut -d '"' -f 4)"
    if [ -n "$zone_id" ]; then
      _zone_id="$zone_id"
      _domain="$h"
      if [ "$i" -gt 1 ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      else
        _sub_domain=""
      fi
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
}

# Usage: _connbyte_rest path json_body
# Sets $response. Returns 1 on transport error or when the API status code is not 2xx.
_connbyte_rest() {
  ep="$1"
  data="$2"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  export _H3="Authorization: Bearer $CONNBYTE_Token"

  _debug ep "$ep"
  _debug2 data "$data"
  response="$(_post "$data" "$CONNBYTE_Api/$ep" "" "POST")"
  ret="$?"
  _debug2 response "$response"

  if [ "$ret" != "0" ]; then
    _err "error $ep"
    return 1
  fi

  status_code="$(echo "$response" | tr -d '\n\r' | _egrep_o "\"status\" *: *\{ *\"code\" *: *[0-9]+" | _egrep_o "[0-9]+$")"
  _debug status_code "$status_code"
  case "$status_code" in
  2*) return 0 ;;
  esac

  _err "ConnByte API error: $response"
  return 1
}
