#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_abion_info='abion.com
Site: abion.com
Options:
 ABION_API_KEY API key for abion.com; obtain it from your Abion account/API settings
'

ABION_Api_Endpoint="https://api.abion.com/v1"

#####################  Public functions #####################

# Usage: dns_abion_add <domain> <txt record>
# Example: dns_abion_add www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_abion_add() {
  fulldomain=$1
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

  if ! _abion_rest PATCH "zones/$_domain" "{\"data\":{\"type\":\"zone\",\"id\":\"$_domain\",\"attributes\":{\"records\":{\"$_sub_domain\":{\"TXT\":[{\"rdata\":\"$txtvalue\",\"ttl\":60}]}}}}}"; then
    return 1
  fi

  if ! echo "$response" | _egrep_o '"id"' > /dev/null; then
    _err "Unexpected API response: $response"
    return 1
  fi

  return 0
}

# Usage: dns_abion_rm <domain> <txt record>
dns_abion_rm() {
  fulldomain=$1
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

  if ! _abion_rest GET "zones/$_domain"; then
    return 1
  fi

  _remaining=$(echo "$response" | _normalizeJson \
    | sed "s/.*\"${_sub_domain}\"://" \
    | _egrep_o '"TXT":\[[^]]*\]' \
    | _egrep_o '"rdata":"[^"]*"' \
    | sed 's/^"rdata":"//;s/"$//' \
    | grep -v "^${txtvalue}$" \
    | sed 's/.*/{"rdata":"&","ttl":60}/' \
    | tr '\n' ',' \
    | sed 's/,$//')

  if ! _abion_rest PATCH "zones/$_domain" "{\"data\":{\"type\":\"zone\",\"id\":\"$_domain\",\"attributes\":{\"records\":{\"$_sub_domain\":{\"TXT\":[${_remaining}]}}}}}"; then
    return 1
  fi

  if ! echo "$response" | _egrep_o '"id"' > /dev/null; then
    _err "Unexpected API response: $response"
    return 1
  fi

  return 0
}

#####################  Private functions #####################

_get_root() {
  domain=$1

  if ! _abion_rest GET "zones" ""; then
    return 1
  fi

  zones=$(echo "$response" | _normalizeJson | sed 's/},{/}\
{/g' | _egrep_o '"id":"[^"]*"' | sed 's/^"id":"//; s/"$//')

  num_labels=$(echo "$domain" | tr '.' '\n' | wc -l | tr -d '[:space:]')
  i=1
  while [ "$i" -le "$num_labels" ]; do
    candidate=$(echo "$domain" | cut -d'.' -f"${i}"-)

    for zone in $zones; do
      if [ "$zone" = "$candidate" ]; then
        _sub_len=$(_math "$i" - 1)
        _sub_domain=$(echo "$domain" | cut -d'.' -f1-"$_sub_len")
        _domain="$candidate"
        return 0
      fi
    done

    i=$(_math "$i" + 1)
  done

  return 1
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
