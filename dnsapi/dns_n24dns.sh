#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_n24dns_info='N24DNS.de
Site: n24dns.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_n24dns
Options:
 N24DNS_Token API token. Create it in the customer portal (API-Tokens).
Issues: github.com/acmesh-official/acme.sh/issues/7429
Author: Benjamin Kaulfuss <support@n24dns.de>
'

N24DNS_API="https://n24dns.de/api/v1"

# TTL of the challenge records. 60 seconds is the highest plan minimum, so
# every plan accepts it, and a value from an earlier run is gone from resolver
# caches before the next validation.
N24DNS_TTL=60

########  Public functions #####################

#Usage: dns_n24dns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_n24dns_add() {
  # The API stores names in lower case.
  fulldomain=$(echo "$1" | _lower_case)
  txtvalue=$2

  _info "Using N24DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _n24dns_load_token; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _n24dns_get_root "$fulldomain"; then
    if [ "$_n24dns_code" = "200" ]; then
      _err "No active zone found for $fulldomain in your N24DNS account."
    fi
    return 1
  fi
  _debug _zone_id "$_zone_id"
  _debug _domain "$_domain"

  _info "Adding TXT record"
  # The API takes the full record name. Several TXT records with the same
  # name are fine (wildcard certificates need two).
  _data="{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"ttl\":$N24DNS_TTL}"
  if _n24dns_rest POST "zones/$_zone_id/records" "$_data"; then
    if _contains "$response" "\"id\":\""; then
      _info "TXT record added."
      return 0
    fi
    _err "Unexpected response while adding TXT record."
    _debug response "$response"
    return 1
  fi

  # 409 record_exists: this exact record is already there, e.g. after a retry.
  if [ "$_n24dns_code" = "409" ] && _contains "$response" "\"error\":\"record_exists\""; then
    _info "TXT record already exists, nothing to do."
    return 0
  fi

  _err "Could not add TXT record."
  return 1
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_n24dns_rm() {
  # The API stores names in lower case.
  fulldomain=$(echo "$1" | _lower_case)
  txtvalue=$2

  _info "Using N24DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _n24dns_load_token; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _n24dns_get_root "$fulldomain"; then
    if [ "$_n24dns_code" = "200" ]; then
      _err "No active zone found for $fulldomain in your N24DNS account."
    fi
    return 1
  fi
  _debug _zone_id "$_zone_id"
  _debug _domain "$_domain"

  if ! _n24dns_rest GET "zones/$_zone_id/records"; then
    _err "Could not list records."
    return 1
  fi

  # One flat JSON object per record, split into one record per line first:
  # without "grep -o" (Solaris) _egrep_o returns only the last match of a
  # line. Only the record with exactly this name and value is removed: for a
  # wildcard certificate a second TXT record with the same name must stay
  # until its own removal. The API returns the TXT content without
  # surrounding quotes, as it was sent.
  _record_id=$(printf "%s" "$response" | tr '{' '\n' | grep "\"name\":\"$fulldomain\"" | grep "\"type\":\"TXT\"" | grep "\"content\":\"$txtvalue\"" | _head_n 1 | _egrep_o "\"id\":\"[^\"]*\"" | cut -d '"' -f 4)
  _debug _record_id "$_record_id"

  if [ -z "$_record_id" ]; then
    _info "TXT record not found, nothing to remove."
    return 0
  fi

  if ! _n24dns_rest DELETE "zones/$_zone_id/records/$_record_id"; then
    # Removed in the meantime: the goal is reached.
    if [ "$_n24dns_code" = "404" ]; then
      _info "TXT record already removed."
      return 0
    fi
    _err "Could not remove TXT record."
    return 1
  fi

  _info "TXT record removed."
  return 0
}

####################  Private functions below ##################################

_n24dns_load_token() {
  N24DNS_Token="${N24DNS_Token:-$(_readaccountconf_mutable N24DNS_Token)}"
  if [ -z "$N24DNS_Token" ]; then
    N24DNS_Token=""
    _err "You didn't specify a N24DNS API token yet."
    _err "Create one in the N24DNS customer portal (API-Tokens) and export N24DNS_Token."
    return 1
  fi
  _saveaccountconf_mutable N24DNS_Token "$N24DNS_Token"
  return 0
}

#_acme-challenge.www.domain.com
#returns
# _domain=domain.com
# _zone_id=3f2b...
_n24dns_get_root() {
  domain=$1
  i=1

  if ! _n24dns_rest GET "zones"; then
    return 1
  fi
  _zones="$response"

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    # Dots escaped: "a.example.com" must not match a zone "aXexample.com".
    _h_re=$(printf "%s" "$h" | sed 's/\./\\./g')
    # One zone per line, for the same reason as in dns_n24dns_rm.
    _zone=$(printf "%s" "$_zones" | tr '{' '\n' | grep "\"name\":\"$_h_re\"" | _head_n 1)
    if [ "$_zone" ]; then
      _zone_id=$(printf "%s" "$_zone" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d '"' -f 4)
      if [ -z "$_zone_id" ]; then
        return 1
      fi
      if ! _contains "$_zone" "\"status\":\"active\""; then
        _err "The zone $h is not active (not verified yet or disabled)."
        return 1
      fi
      _domain=$h
      return 0
    fi
    i=$(_math "$i" + 1)
  done
  return 1
}

#Usage: method endpoint [data]
#returns
# response       body, normalized
# _n24dns_code   HTTP status code
_n24dns_rest() {
  m=$1
  ep=$2
  data=$3
  _debug "$m" "$ep"

  export _H1="Authorization: Bearer $N24DNS_Token"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$N24DNS_API/$ep" "" "$m")"
    _ret="$?"
  else
    response="$(_get "$N24DNS_API/$ep")"
    _ret="$?"
  fi
  _n24dns_code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug2 _n24dns_code "$_n24dns_code"

  if [ "$_ret" != "0" ]; then
    _err "Error calling $m $ep"
    return 1
  fi

  response="$(printf "%s" "$response" | _normalizeJson)"
  _debug2 response "$response"

  # The status code decides. Errors come as {"error":"<code>","message":"..."}
  # or, for requests the API could not parse (422), as {"detail":[...]}.
  case "$_n24dns_code" in
  2*)
    return 0
    ;;
  401)
    _err "N24DNS API: the token was not accepted. Check N24DNS_Token."
    ;;
  429)
    _err "N24DNS API: too many requests, try again later."
    ;;
  404 | 409)
    # Left to the caller: "already there" and "already gone" are no errors.
    _debug "N24DNS API answered HTTP $_n24dns_code: $response"
    ;;
  *)
    _err "N24DNS API error (HTTP $_n24dns_code): $response"
    ;;
  esac
  return 1
}
