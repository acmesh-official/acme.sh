#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_abion_info='abion.com
Site: abion.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_abion
Options:
 ABION_API_KEY API key for abion.com; obtain it from your Abion account/API settings
'

ABION_Api_Endpoint="https://api.abion.com/v1"

#####################  Public functions #####################

# Usage: dns_abion_add <domain> <txt record>
# Example: dns_abion_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_abion_add() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  ABION_API_KEY="${ABION_API_KEY:-$(_readaccountconf_mutable ABION_API_KEY)}"

  if [ -z "$ABION_API_KEY" ]; then
    ABION_API_KEY=""
    _err "You need to specify ABION_API_KEY."
    return 1
  fi

  _saveaccountconf_mutable ABION_API_KEY "$ABION_API_KEY"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if ! _abion_get_txt_records; then
    return 1
  fi

  if _contains "$_txt_records" "\"rdata\":\"$txtvalue\""; then
    _info "TXT record already exists"
    return 0
  fi

  _records=$(echo "$_txt_records" | tr '\n' ',' | sed 's/,*$//')
  if [ -n "$_records" ]; then
    _records="$_records,"
  fi

  _info "Adding record"
  if ! _abion_patch_txt "[$_records{\"rdata\":\"$txtvalue\",\"ttl\":60}]"; then
    return 1
  fi

  _info "Added, OK"
  return 0
}

# Usage: dns_abion_rm <domain> <txt record>
dns_abion_rm() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  ABION_API_KEY="${ABION_API_KEY:-$(_readaccountconf_mutable ABION_API_KEY)}"

  if [ -z "$ABION_API_KEY" ]; then
    ABION_API_KEY=""
    _err "You need to specify ABION_API_KEY."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if ! _abion_get_txt_records; then
    return 1
  fi

  if ! _contains "$_txt_records" "\"rdata\":\"$txtvalue\""; then
    _info "TXT record not found, nothing to remove"
    return 0
  fi

  _records=$(echo "$_txt_records" | grep -v "\"rdata\":\"$txtvalue\"" | tr '\n' ',' | sed 's/,*$//')

  if [ -n "$_records" ]; then
    _records="[$_records]"
  else
    _records="null"
  fi

  _info "Deleting record"
  if ! _abion_patch_txt "$_records"; then
    return 1
  fi

  _info "Deleted, OK"
  return 0
}

#####################  Private functions #####################

_get_root() {
  domain=$1
  i=1
  p=0
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi

    if ! _abion_rest GET "zones/$h"; then
      return 1
    fi

    if _contains "$response" '"type" *: *"zone"'; then
      if [ "$p" = "0" ]; then
        _sub_domain="@"
      else
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      fi
      _domain="$h"
      return 0
    fi

    if ! _contains "$response" "Zone not found"; then
      _err "$response"
      return 1
    fi

    p="$i"
    i=$(_math "$i" + 1)
  done
}

_abion_get_txt_records() {
  if ! _abion_rest GET "zones/$_domain"; then
    return 1
  fi

  _sub_re=$(printf "%s" "$_sub_domain" | sed 's/[.]/\\./g')
  _txt_records=$(echo "$response" | _normalizeJson |
    sed -n "s/.*\"$_sub_re\":{//p" |
    sed 's/\] *}.*/]/' |
    _egrep_o '"TXT":\[[^]]*\]' |
    sed 's/^"TXT":\[ *//;s/ *\]$//;s/} *, *{/}\
{/g')
  _debug2 _txt_records "$_txt_records"
  return 0
}

_abion_patch_txt() {
  if ! _abion_rest PATCH "zones/$_domain" "{\"data\":{\"type\":\"zone\",\"id\":\"$_domain\",\"attributes\":{\"records\":{\"$_sub_domain\":{\"TXT\":$1}}}}}"; then
    return 1
  fi

  if ! _contains "$response" '"type" *: *"zone"'; then
    _err "Unexpected API response: $response"
    return 1
  fi

  return 0
}

_abion_rest() {
  method=$1
  endpoint=$2
  data=$3

  export _H1="X-API-KEY: $ABION_API_KEY"
  export _H2="Content-Type: application/json"

  if [ "$method" = "GET" ]; then
    response="$(_get "$ABION_Api_Endpoint/$endpoint")"
  else
    response="$(_post "$data" "$ABION_Api_Endpoint/$endpoint" "" "$method")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $endpoint"
    return 1
  fi

  _debug2 response "$response"
  return 0
}
