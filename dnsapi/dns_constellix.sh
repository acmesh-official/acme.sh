#!/usr/bin/env sh

# Author: Wout Decre <wout@rambla.be>

CONSTELLIX_API="https://api.dns.constellix.com/v1"
#CONSTELLIX_KEY="XXX"
#CONSTELLIX_SECRET="XXX"

########  Public functions #####################

dns_constellix_add() {
  fulldomain=$1
  txtvalue=$2

  CONSTELLIX_KEY="${CONSTELLIX_KEY:-$(_readaccountconf_mutable CONSTELLIX_KEY)}"
  CONSTELLIX_SECRET="${CONSTELLIX_SECRET:-$(_readaccountconf_mutable CONSTELLIX_SECRET)}"

  if [ -z "$CONSTELLIX_KEY" ] || [ -z "$CONSTELLIX_SECRET" ]; then
    _err "You did not specify the Contellix API key and secret yet."
    return 1
  fi

  _saveaccountconf_mutable CONSTELLIX_KEY "$CONSTELLIX_KEY"
  _saveaccountconf_mutable CONSTELLIX_SECRET "$CONSTELLIX_SECRET"

  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _info "Adding TXT record"
  if _constellix_rest POST "domains/${_domain_id}/records" "[{\"type\":\"txt\",\"add\":true,\"set\":{\"name\":\"${_sub_domain}\",\"ttl\":120,\"roundRobin\":[{\"value\":\"${txtvalue}\"}]}}]"; then
    if printf -- "%s" "$response" | grep "{\"success\":\"1 record(s) added, 0 record(s) updated, 0 record(s) deleted\"}" >/dev/null; then
      _info "Added"
      return 0
    else
      _err "Error adding TXT record"
      return 1
    fi
  fi
}

dns_constellix_rm() {
  fulldomain=$1
  txtvalue=$2

  CONSTELLIX_KEY="${CONSTELLIX_KEY:-$(_readaccountconf_mutable CONSTELLIX_KEY)}"
  CONSTELLIX_SECRET="${CONSTELLIX_SECRET:-$(_readaccountconf_mutable CONSTELLIX_SECRET)}"

  if [ -z "$CONSTELLIX_KEY" ] || [ -z "$CONSTELLIX_SECRET" ]; then
    _err "You did not specify the Contellix API key and secret yet."
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _info "Removing TXT record"
  if _constellix_rest POST "domains/${_domain_id}/records" "[{\"type\":\"txt\",\"delete\":true,\"filter\":{\"field\":\"name\",\"op\":\"eq\",\"value\":\"${_sub_domain}\"}}]"; then
    if printf -- "%s" "$response" | grep "{\"success\":\"0 record(s) added, 0 record(s) updated, 1 record(s) deleted\"}" >/dev/null; then
      _info "Removed"
      return 0
    else
      _err "Error removing TXT record"
      return 1
    fi
  fi
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=2
  p=1
  _debug "Detecting root zone"
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      return 1
    fi

    if ! _constellix_rest GET "domains"; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _domain_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":[^,]*" | head -n 1 | cut -d ':' -f 2 | tr -d '}')
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d '.' -f 1-$p)
        _domain="$h"

        _debug _domain_id "$_domain_id"
        _debug _sub_domain "$_sub_domain"
        _debug _domain "$_domain"
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_constellix_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  rdate=$(date +"%s")"000"
  hmac=$(printf "%s" "$rdate" | _hmac sha1 "$(printf "%s" "$CONSTELLIX_SECRET" | _hex_dump | tr -d ' ')" | _base64)

  export _H1="x-cnsdns-apiKey: $CONSTELLIX_KEY"
  export _H2="x-cnsdns-requestDate: $rdate"
  export _H3="x-cnsdns-hmac: $hmac"
  export _H4="Accept: application/json"
  export _H5="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$CONSTELLIX_API/$ep" "" "$m")"
  else
    response="$(_get "$CONSTELLIX_API/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "Error $ep"
    return 1
  fi

  _debug response "$response"
  return 0
}
