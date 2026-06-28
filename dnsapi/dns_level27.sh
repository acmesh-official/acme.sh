#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_level27_info='Level27
Site: Level27.be
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_level27
Options:
 LEVEL27_API_KEY API key. Get one from the Level27 control panel (https://app.level27.eu/account/profile/security).
OptionsAlt:
 LEVEL27_API API base URL. Optional. Default "https://api.level27.eu/v1".
Issues: github.com/acmesh-official/acme.sh/issues
Author: Jeroen Moors <jeroen.moors@level27.be>
'

LEVEL27_API_DEFAULT="https://api.level27.eu/v1"

########  Public functions #####################

# Usage: dns_level27_add _acme-challenge.www.example.com "TXT-value"
dns_level27_add() {
  fulldomain="$(_idn "$1")"
  txtvalue="$2"

  _info "Using Level27 to add a TXT record for $fulldomain"

  if ! _level27_init; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Could not determine the root zone for $fulldomain at Level27."
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _level27_data="{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\"}"
  if ! _level27_rest POST "domains/$_domain_id/records" "$_level27_data"; then
    _err "Could not add the TXT record."
    return 1
  fi

  if _contains "$response" "\"id\":"; then
    _info "TXT record added."
    return 0
  fi

  _err "Unexpected response while adding the TXT record."
  return 1
}

# Usage: dns_level27_rm _acme-challenge.www.example.com "TXT-value"
dns_level27_rm() {
  fulldomain="$(_idn "$1")"
  txtvalue="$2"

  _info "Using Level27 to remove the TXT record for $fulldomain"

  if ! _level27_init; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Could not determine the root zone for $fulldomain at Level27."
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if ! _level27_rest GET "domains/$_domain_id/records?type=TXT"; then
    _err "Could not list the existing TXT records."
    return 1
  fi

  _record_id="$(_level27_find_record_id "$response" "$txtvalue")"
  if [ -z "$_record_id" ]; then
    _info "No matching TXT record found; nothing to remove."
    return 0
  fi
  _debug _record_id "$_record_id"

  if ! _level27_rest DELETE "domains/$_domain_id/records/$_record_id"; then
    _err "Could not remove the TXT record."
    return 1
  fi

  _info "TXT record removed."
  return 0
}

####################  Private functions below ##################################

# Reads and validates the API credentials and endpoint, and stores them for renewals.
_level27_init() {
  LEVEL27_API_KEY="${LEVEL27_API_KEY:-$(_readaccountconf_mutable LEVEL27_API_KEY)}"
  if [ -z "$LEVEL27_API_KEY" ]; then
    LEVEL27_API_KEY=""
    _err "You must export the variable LEVEL27_API_KEY before using the Level27 DNS API."
    _err "Get an API key from the Level27 control panel (https://app.level27.eu/account/profile/security)."
    return 1
  fi
  LEVEL27_API_KEY="$(echo "$LEVEL27_API_KEY" | tr -d '"')"
  _saveaccountconf_mutable LEVEL27_API_KEY "$LEVEL27_API_KEY"

  LEVEL27_API="${LEVEL27_API:-$(_readaccountconf_mutable LEVEL27_API)}"
  if [ -z "$LEVEL27_API" ]; then
    LEVEL27_API="$LEVEL27_API_DEFAULT"
  fi
  _saveaccountconf_mutable LEVEL27_API "$LEVEL27_API"

  # Remove a trailing slash so endpoints can be appended consistently.
  LEVEL27_API="$(echo "$LEVEL27_API" | sed 's#/$##')"
  return 0
}

# Usage: _get_root _acme-challenge.www.example.com
# Splits the full domain into the registered zone and the subdomain part.
# Sets: _domain, _domain_id, _sub_domain
_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      # not valid
      return 1
    fi

    if ! _level27_rest GET "domains?filter=$h"; then
      return 1
    fi

    _level27_zones="$(echo "$response" | _normalizeJson)"
    if _contains "$_level27_zones" "\"fullname\":\"$h\""; then
      _domain_line="$(echo "$_level27_zones" | sed 's/},{/}\n{/g' | grep "\"fullname\":\"$h\"" | _head_n 1)"
      _domain_id="$(echo "$_domain_line" | _egrep_o '"id":[0-9]*' | _head_n 1 | cut -d : -f 2)"
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

# Usage: _level27_find_record_id "<records-json>" "<txtvalue>"
# Prints the id of the TXT record whose content matches the value, or nothing.
_level27_find_record_id() {
  _records="$(echo "$1" | _normalizeJson | sed 's/},{/}\n{/g')"
  _wanted="$2"
  _record_line="$(echo "$_records" | grep "\"content\":\"$_wanted\"" | _head_n 1)"
  if [ -z "$_record_line" ]; then
    # Some APIs store TXT content wrapped in quotes.
    _record_line="$(echo "$_records" | grep "\"content\":\"\\\\\"$_wanted\\\\\"\"" | _head_n 1)"
  fi
  if [ -z "$_record_line" ]; then
    return 0
  fi
  echo "$_record_line" | _egrep_o '"id":[0-9]*' | _head_n 1 | cut -d : -f 2
}

# Usage: _level27_rest <method> <endpoint> [data]
# Performs an authenticated API call and stores the body in $response.
_level27_rest() {
  m="$1"
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Authorization: $LEVEL27_API_KEY"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  if [ "$m" != "GET" ]; then
    _debug2 data "$data"
    response="$(_post "$data" "$LEVEL27_API/$ep" "" "$m")"
  else
    response="$(_get "$LEVEL27_API/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "Error querying the Level27 API endpoint: $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
