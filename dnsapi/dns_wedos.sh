#!/usr/bin/env sh
#
# WEDOS DNS WAPI
# https://hosting.wedos.com/en/
#
# Author: Ondřej Budín
# Report Bugs here: https://github.com/obud/acme.sh
#
# --
# export WEDOS_Email="customer@example.com"
# export WEDOS_ApiPassword="1l+C+}mcFT0c38"
# --

WEDOS_URL="https://api.wedos.com/wapi/json"
WEDOS_PREFIX="WEDOS WAPI:"

##################################
#        Private functions       #
##################################

_wedos_init() {
  WEDOS_Email="${WEDOS_Email:-$(_readaccountconf_mutable WEDOS_Email)}"
  WEDOS_ApiPassword="${WEDOS_ApiPassword:-$(_readaccountconf_mutable WEDOS_ApiPassword)}"
  if [ -z "$WEDOS_Email" ] || [ -z "$WEDOS_ApiPassword" ]; then
    WEDOS_Email=""
    WEDOS_ApiPassword=""
    _err "You must export variables: WEDOS_Email and WEDOS_ApiPassword"
    return 1
  fi
  _saveaccountconf_mutable WEDOS_Email "$WEDOS_Email"
  _saveaccountconf_mutable WEDOS_ApiPassword "$WEDOS_ApiPassword"
}

_wedos_call() {
  WEDOS_Auth="$(printf "%s" "$WEDOS_ApiPassword" | _digest sha1 hex)"
  WEDOS_Auth="$(printf "%s" "$WEDOS_Email$WEDOS_Auth$(date --date="TZ=\"Europe/Prague\" today" "+%H")" | _digest sha1 hex)"
  data="request={\"request\":{\"user\":\"$WEDOS_Email\",\"auth\":\"$WEDOS_Auth\",\"command\":\"$1\",\"clTRID\":\"acme.sh - WEDOS WAPI\",\"data\":$data}}"
  _debug data "$data"
  response="$(_post "$data" "$WEDOS_URL" "" "POST")"
  _debug response "$response"
  code=$(printf "%s" "$response" | cut -c 21-24)
  if [ "$code" = "2006" ]; then
    _err "$WEDOS_PREFIX API ERROR. Requests limit exceeded."
    return 1
  fi
  if [ "$code" = "2050" ]; then
    _err "$WEDOS_PREFIX API ERROR. Authentication failure."
    return 1
  fi
  if [ "$code" = "2051" ]; then
    _err "$WEDOS_PREFIX API ERROR. Access not allowed from this IP address."
    return 1
  fi
  if [ "$code" = "2052" ]; then
    _err "$WEDOS_PREFIX API ERROR. IP address temporarily blocked due to too many failed requests."
    return 1
  fi
  if [ "$code" = "2310" ]; then
    _err "$WEDOS_PREFIX API ERROR. DNS domain - rows count limit reached. Please contact WEDOS customer support to increase limit."
    return 1
  fi
  if [ "$code" != "1000" ]; then
    _err "$WEDOS_PREFIX API ERROR."
    _info ""
    _err "RESPONSE: $response"
    return 1
  fi
}

_wedos_get_root() {
  _info "$WEDOS_PREFIX Searching root zone..."
  data="[]"
  if ! _wedos_call "dns-domains-list"; then
    return 1
  fi

  domain=$1
  i=2
  p=1
  while true; do
    candidate=$(printf "%s" "$domain" | cut -d . -f "$i-100")
    _debug candidate "$candidate"

    if [ -z "$candidate" ]; then
      _err "$WEDOS_PREFIX ERROR. Root zone not found."
      return 1
    fi

    if _contains "$response" "\"name\":\"$candidate\"" >/dev/null && _contains "$response" "\"status\":\"active\"" >/dev/null; then
      _domain="$candidate"
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f "1-$p")
      _info "$WEDOS_PREFIX OK."
      _debug _domain "$_domain"
      _debug _sub_domain "$_sub_domain"
      return 0
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

_wedos_get_record_id() {
  _info "$WEDOS_PREFIX Searching DNS record..."
  domain=$1
  sub_domain=$2
  r_data=$3

  data="{\"domain\":\"$domain\"}"
  if ! _wedos_call "dns-rows-list"; then
    return 1
  fi

  if _contains "$response" "\"name\":\"$sub_domain\"" >/dev/null; then
    i=1
    while true; do
      row=$(printf "%s" "$response" | cut -d "}" -f "$i")
      _debug row "$row"

      if [ -z "$row" ]; then
        _err "$WEDOS_PREFIX ERROR."
        return 1
      fi

      if _contains "$row" "\"name\":\"$sub_domain\"" >/dev/null && _contains "$row" "\"rdata\":\"$r_data\"" >/dev/null; then
        _record_id=$(printf "%s" "$row" | _egrep_o "\[*\"ID\":\"[^\"]*\"" | head -n 1 | cut -d : -f 2 | tr -d \")
        if [ "$_record_id" ]; then
          _info "$WEDOS_PREFIX OK."
          return 0
        fi
        _err "$WEDOS_PREFIX ERROR."
        return 1
      fi
      i=$(_math "$i" + 1)
    done
  fi
  _err "$WEDOS_PREFIX ERROR. Record not found."
  return 1
}

_wedos_commit() {
  _info "$WEDOS_PREFIX Committing changes..."
  data="{\"name\":\"$1\"}"
  if ! _wedos_call "dns-domain-commit"; then
    return 1
  fi
  _info "$WEDOS_PREFIX OK."
}

##################################
#        Public functions        #
##################################

dns_wedos_add() {
  if ! _wedos_init; then
    return 1
  fi
  _info "$WEDOS_PREFIX $1"
  if ! _wedos_get_root "$1"; then
    return 1
  fi
  _info "$WEDOS_PREFIX Adding record..."
  data="{\"domain\":\"$_domain\",\"name\":\"$_sub_domain\",\"ttl\":300,\"type\":\"TXT\",\"rdata\":\"$2\"}"
  if ! _wedos_call "dns-row-add"; then
    return 1
  fi
  _info "$WEDOS_PREFIX OK."
  if ! _wedos_commit "$_domain"; then
    return 1
  fi
}

dns_wedos_rm() {
  if ! _wedos_init; then
    return 1
  fi
  _info "$WEDOS_PREFIX $1"
  if ! _wedos_get_root "$1"; then
    return 1
  fi
  if ! _wedos_get_record_id "$_domain" "$_sub_domain" "$2"; then
    return 1
  fi

  _info "$WEDOS_PREFIX Removing record..."
  data="{\"domain\":\"$_domain\",\"row_id\":\"$_record_id\"}"
  if ! _wedos_call "dns-row-delete"; then
    return 1
  fi
  _info "$WEDOS_PREFIX OK."

  if ! _wedos_commit "$_domain"; then
    return 1
  fi
}