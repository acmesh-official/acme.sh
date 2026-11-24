#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_glesys_info='Glesys
Site: Glesys.se
Docs: https://github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_glesys
Options:
 GLESYS_API_KEY Generated API key.
 GLESYS_PROJECT_ID Project ID for the API key (e.g. cl12345).
 GLESYS_API API endpoint. Default "https://api.glesys.com/domain".
 GLESYS_TTL TXT record TTL. Default 120.
Issues: https://github.com/acmesh-official/acme.sh/issues/7057
Author: Toni Karppi
'

GLESYS_API_DEFAULT="https://api.glesys.com/domain"
GLESYS_TTL_DEFAULT="120"

######## Public functions #####################################################

# Usage:
#   dns_glesys_add _acme-challenge.www.example.com "txt-value"
dns_glesys_add() {
  fulldomain="$1"
  txtvalue="$2"

  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _glesys_init || return 1

  if ! _glesys_get_root "$fulldomain"; then
    _err "Could not find root zone for $fulldomain"
    return 1
  fi

  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  host_value="${_sub_domain:-@}"
  _debug _host_value "$host_value"

  data="{\"domainname\":\"$_domain\",\"host\":\"$host_value\",\"type\":\"TXT\",\"data\":\"$txtvalue\",\"ttl\":\"$GLESYS_TTL\"}"

  _debug2 data "$data"

  if ! _glesys_rest POST "/addrecord" "$data"; then
    _err "Failed to send HTTP request to add TXT record"
    return 1
  fi

  response_code=$(
    printf "%s" "$response" |
      tr -d '\r\n\t ' |
      _egrep_o '"code":"?[0-9]+' |
      _egrep_o '[0-9]+$'
  )

  _debug response_code "$response_code"

  if [ "$response_code" != "200" ]; then
    _err "GleSYS API responded with an unexpected status when attempting to add TXT record"
    _debug2 "API response" "$response"
    return 1
  fi

  _info "TXT record added"

  return 0
}

# Usage:
#   dns_glesys_rm _acme-challenge.www.example.com "txt-value"
dns_glesys_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _glesys_init || return 1

  if ! _glesys_get_root "$fulldomain"; then
    _err "Could not find root zone for $fulldomain"
    return 1
  fi

  if ! _glesys_find_record_id "$txtvalue"; then
    _info "TXT record not present, skip removal"
    return 0
  fi

  _debug _record_id "$_record_id"

  if ! _glesys_rest POST "/deleterecord" "{\"recordid\":$_record_id}"; then
    _err "Failed to send HTTP request to remove TXT record"
    return 1
  fi

  response_code=$(
    printf "%s" "$response" |
      tr -d '\r\n\t ' |
      _egrep_o '"code":"?[0-9]+' |
      _egrep_o '[0-9]+$'
  )

  _debug response_code "$response_code"

  if [ "$response_code" != "200" ]; then
    _err "GleSYS API responded with unexpected status when attempting to remove TXT record"
    _debug2 "API response" "$response"
    return 1
  fi

  _info "TXT record removed"

  return 0
}

######## Private functions ####################################################

_glesys_find_record_id() {
  txtvalue="$1"

  _debug txtvalue "$txtvalue"

  if [ -z "$txtvalue" ]; then
    return 1
  fi

  _record_id=""

  _debug "Looking for TXT record with value" "$txtvalue"

  if ! _glesys_rest GET "/listrecords?domainname=$_domain"; then
    _err "Failed to list DNS records"
    return 1
  fi

  records="$(
    printf "%s" "$response" |
      tr -d '\r\n\t ' |
      sed 's/},{/}\
{/g'
  )"

  _debug2 records "$records"

  expected_data="\"data\":\"$txtvalue\""

  _record_id="$(
    printf "%s\n" "$records" |
      while IFS= read -r record; do
        printf "%s" "$record" | grep -q '"type":"TXT"' || continue
        printf "%s" "$record" | grep -Fq "$expected_data" || continue

        printf "%s" "$record" |
          grep -E -o '"recordid":"?[0-9]+' |
          grep -E -o '[0-9]+$'

        break
      done
  )"

  _debug _record_id "$_record_id"

  if [ -z "$_record_id" ]; then
    return 1
  fi

  return 0
}

# Finds:
#   _domain     example.com
#   _sub_domain _acme-challenge.www
_glesys_get_root() {
  domain="$1"
  i=1

  while true; do
    h="$(printf "%s" "$domain" | cut -d . -f "$i"-100)"

    if [ -z "$h" ]; then
      return 1
    fi

    if _glesys_rest GET "/listrecords?domainname=$h"; then
      response_code=$(
        printf "%s" "$response" |
          tr -d '\r\n\t ' |
          _egrep_o '"code":"?[0-9]+' |
          _egrep_o '[0-9]+$'
      )

      _debug response_code "$response_code"

      if [ "$response_code" = "200" ]; then
        cut_len="$((${#domain} - ${#h} - 1))"
        _domain="$h"
        _sub_domain="$(printf "%s" "$domain" | cut -c "1-$cut_len")"
        return 0
      fi
    fi

    i="$((i + 1))"
  done
}

_glesys_init() {
  [ -z "$GLESYS_API" ] && GLESYS_API="$GLESYS_API_DEFAULT"
  [ -z "$GLESYS_TTL" ] && GLESYS_TTL="$GLESYS_TTL_DEFAULT"

  _debug GLESYS_API "$GLESYS_API"
  _debug GLESYS_TTL "$GLESYS_TTL"

  GLESYS_API_KEY="${GLESYS_API_KEY:-$(_readaccountconf_mutable GLESYS_API_KEY)}"
  GLESYS_PROJECT_ID="${GLESYS_PROJECT_ID:-$(_readaccountconf_mutable GLESYS_PROJECT_ID)}"

  if [ -z "$GLESYS_API_KEY" ] || [ -z "$GLESYS_PROJECT_ID" ]; then
    _err "GLESYS_API_KEY and GLESYS_PROJECT_ID must be set for this provider"
    return 1
  fi

  _secure_debug GLESYS_API_KEY "$GLESYS_API_KEY"
  _secure_debug GLESYS_PROJECT_ID "$GLESYS_PROJECT_ID"

  _glesys_basic_auth="$(printf "%s:%s" "$GLESYS_PROJECT_ID" "$GLESYS_API_KEY" | _base64)"
  _secure_debug2 _glesys_basic_auth "$_glesys_basic_auth"

  _saveaccountconf_mutable GLESYS_API_KEY "$GLESYS_API_KEY"
  _saveaccountconf_mutable GLESYS_PROJECT_ID "$GLESYS_PROJECT_ID"

  return 0
}

_glesys_rest() {
  method="$1"
  path="$2"
  data="$3"

  export _H1="Authorization: Basic $_glesys_basic_auth"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  url="$GLESYS_API$path"
  _debug "$method $url"

  if [ "$method" = "GET" ]; then
    response="$(_get "$url")"
  else
    response="$(_post "$data" "$url" "" "$method")"
  fi

  ret="$?"
  _debug2 response "$response"
  _debug ret "$ret"

  if [ "$ret" != "0" ]; then
    return 1
  fi

  return 0
}
