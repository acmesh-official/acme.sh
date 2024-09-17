#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_mijnhost_info='mijn.host
Domains: mijn.host
Site: mijn.host
Docs: https://mijn.host/api/doc/api-3563900
Options:
 MIJN_HOST_API_KEY API Key
 MIJN_HOST_ENDPOINT_API API Endpoint URL. E.g. "https://mijn.host/api/v2"
'

########  Public functions #####################

# Usage: dns_mijnhost_add _acme-challenge.www.domain.com "TXT_RECORD_VALUE"
dns_mijnhost_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using mijn.host API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  MIJN_HOST_API_KEY="${MIJN_HOST_API_KEY:-$(_readaccountconf_mutable MIJN_HOST_API_KEY)}"
  MIJN_HOST_ENDPOINT_API="${MIJN_HOST_ENDPOINT_API:-$(_readaccountconf_mutable MIJN_HOST_ENDPOINT_API)}"
  
  if [ -z "$MIJN_HOST_API_KEY" ] || [ -z "$MIJN_HOST_ENDPOINT_API" ]; then
    _err "You didn't specify mijn.host API key or API endpoint yet."
    return 1
  fi

  _saveaccountconf_mutable MIJN_HOST_API_KEY "$MIJN_HOST_API_KEY"
  _saveaccountconf_mutable MIJN_HOST_ENDPOINT_API "$MIJN_HOST_ENDPOINT_API"

  _debug "Fetching DNS zone for $fulldomain"
  if ! _get_root "$fulldomain" "$MIJN_HOST_ENDPOINT_API"; then
    _err "Invalid domain"
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  _info "Adding TXT record"
  body="{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"ttl\":300}"
  if _mijnhost_rest POST "$MIJN_HOST_ENDPOINT_API/dnszones/$_domain/records" "$body"; then
    if _contains "$response" "\"content\":\"$txtvalue\""; then
      _info "TXT record added successfully"
      return 0
    else
      _err "Failed to add TXT record"
      return 1
    fi
  fi

  _err "Error adding TXT record"
  return 1
}

# Usage: dns_mijnhost_rm _acme-challenge.www.domain.com "TXT_RECORD_VALUE"
dns_mijnhost_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using mijn.host API to remove record"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  MIJN_HOST_API_KEY="${MIJN_HOST_API_KEY:-$(_readaccountconf_mutable MIJN_HOST_API_KEY)}"
  MIJN_HOST_ENDPOINT_API="${MIJN_HOST_ENDPOINT_API:-$(_readaccountconf_mutable MIJN_HOST_ENDPOINT_API)}"

  if [ -z "$MIJN_HOST_API_KEY" ] || [ -z "$MIJN_HOST_ENDPOINT_API" ]; then
    _err "You didn't specify mijn.host API key or API endpoint yet."
    return 1
  fi

  _saveaccountconf_mutable MIJN_HOST_API_KEY "$MIJN_HOST_API_KEY"
  _saveaccountconf_mutable MIJN_HOST_ENDPOINT_API "$MIJN_HOST_ENDPOINT_API"

  _debug "Fetching DNS zone for $fulldomain"
  if ! _get_root "$fulldomain" "$MIJN_HOST_ENDPOINT_API"; then
    _err "Invalid domain"
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  _debug "Fetching existing TXT records"
  if ! _mijnhost_rest GET "$MIJN_HOST_ENDPOINT_API/dnszones/$_domain/records"; then
    _err "Error fetching records"
    return 1
  fi

  record_id=$(printf "%s" "$response" | grep "\"content\":\"$txtvalue\"" | cut -d'"' -f4)
  if [ -z "$record_id" ]; then
    _err "Could not find record to remove"
    return 1
  fi

  _info "Removing TXT record"
  if _mijnhost_rest DELETE "$MIJN_HOST_ENDPOINT_API/dnszones/$_domain/records/$record_id"; then
    _info "Record deleted successfully"
    return 0
  else
    _err "Failed to delete record"
    return 1
  fi
}

####################  Private functions ########################

_mijnhost_rest() {
  method=$1
  endpoint=$2
  data=$3

  export _H1="Authorization: Bearer $MIJN_HOST_API_KEY"
  export _H2="Content-Type: application/json"

  _debug "$endpoint"
  if [ "$method" = "GET" ]; then
    response="$(_get "$endpoint")"
  else
    response="$(_post "$data" "$endpoint" "" "$method")"
  fi

  if [ $? -ne 0 ]; then
    _err "API request failed"
    return 1
  fi

  _secure_debug response "$response"
  return 0
}

_get_root() {
  domain=$1
  api_endpoint=$2
  i=2
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug "Testing root domain $h"

    if ! _mijnhost_rest GET "$api_endpoint/dnszones?name=$h"; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _domain=$h
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$((i - 1)))
      return 0
    fi

    i=$((i + 1))
  done

  return 1
}
