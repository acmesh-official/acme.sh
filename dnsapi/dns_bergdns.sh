#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_bergdns_info='bergdns.at
Site: bergdns.at
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_bergdns
Options:
 BERGDNS_API_KEY API key, as issued in the account UI. Needs read (to find the zone and the record) and write over the challenge names.
 BERGDNS_API_URL API base URL. Optional. Default "https://bergdns.at/v1".
 BERGDNS_TTL TTL of the challenge record, in seconds. Optional. Default "60".
 BERGDNS_PROPAGATION_TIMEOUT Seconds to wait for the record to reach every secondary. Optional. Default "120". "0" does not wait.
Issues: github.com/acmesh-official/acme.sh/issues/7261
Author: Kenny Kropp <https://github.com/kekropp>
'

_BERGDNS_DEFAULT_URL='https://bergdns.at/v1'
_BERGDNS_DEFAULT_TTL='60'
_BERGDNS_DEFAULT_WAIT='120'

########  Public functions  ####################################################

# Usage: dns_bergdns_add _acme-challenge.www.example.com "token"
# The value is added to the RRset, so a domain and its wildcard can be
# validated at the same time.
dns_bergdns_add() {
  fulldomain=$(echo "$1" | _lower_case)
  txtvalue=$2

  _bergdns_init || return 1
  _bergdns_find_zone "$fulldomain" || return 1
  _bergdns_find_rrset "$fulldomain" || return 1

  _info "Adding TXT $fulldomain in zone $_bergdns_zone_name"
  if [ -z "$_bergdns_rrset_id" ]; then
    if _bergdns_rest POST "zones/$_bergdns_zone_id/rrsets" \
      "{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"ttl\":$BERGDNS_TTL,\"records\":[\"\\\"$txtvalue\\\"\"]}"; then
      _bergdns_rrset_id=$(echo "$response" | _egrep_o '"id":"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
      _bergdns_wait "$fulldomain"
      return 0
    fi
    if [ "$_bergdns_code" != "rrset_exists" ]; then
      _err "bergdns: could not add the challenge record: $_bergdns_error"
      return 1
    fi
    # another run created it since the lookup above
    _bergdns_find_rrset "$fulldomain" || return 1
    if [ -z "$_bergdns_rrset_id" ]; then
      _err "bergdns: could not find the challenge record at $fulldomain"
      return 1
    fi
  fi

  if ! _bergdns_rest POST \
    "zones/$_bergdns_zone_id/rrsets/$_bergdns_rrset_id/records" \
    "{\"records\":[\"\\\"$txtvalue\\\"\"]}"; then
    _err "bergdns: could not add the challenge record: $_bergdns_error"
    return 1
  fi

  _bergdns_wait "$fulldomain"
}

# Usage: dns_bergdns_rm _acme-challenge.www.example.com "token"
# Only this value is removed. Removing the last value deletes the RRset, and
# removing a value that does not exist is not an error.
dns_bergdns_rm() {
  fulldomain=$(echo "$1" | _lower_case)
  txtvalue=$2

  _bergdns_init || return 1
  _bergdns_find_zone "$fulldomain" || return 1
  _bergdns_find_rrset "$fulldomain" || return 1

  if [ -z "$_bergdns_rrset_id" ]; then
    _info "bergdns: no TXT records at $fulldomain, nothing to remove"
    return 0
  fi

  _info "Removing TXT $fulldomain from zone $_bergdns_zone_name"
  if ! _bergdns_rest DELETE \
    "zones/$_bergdns_zone_id/rrsets/$_bergdns_rrset_id/records" \
    "{\"records\":[\"\\\"$txtvalue\\\"\"]}"; then
    if [ "$_bergdns_code" = "rrset_not_found" ]; then
      return 0
    fi
    _err "bergdns: could not remove the challenge record: $_bergdns_error"
    return 1
  fi
  return 0
}

########  Private functions  ###################################################

_bergdns_init() {
  BERGDNS_API_KEY="${BERGDNS_API_KEY:-$(_readaccountconf_mutable BERGDNS_API_KEY)}"
  BERGDNS_API_URL="${BERGDNS_API_URL:-$(_readaccountconf_mutable BERGDNS_API_URL)}"
  BERGDNS_TTL="${BERGDNS_TTL:-$(_readaccountconf_mutable BERGDNS_TTL)}"
  BERGDNS_PROPAGATION_TIMEOUT="${BERGDNS_PROPAGATION_TIMEOUT:-$(_readaccountconf_mutable BERGDNS_PROPAGATION_TIMEOUT)}"

  if [ -z "$BERGDNS_API_KEY" ]; then
    BERGDNS_API_KEY=""
    _clearaccountconf_mutable BERGDNS_API_KEY
    _err "You have not set BERGDNS_API_KEY. Create a key in the bergdns UI and export it:"
    _err "  export BERGDNS_API_KEY=\"bgd_...\""
    return 1
  fi

  [ -n "$BERGDNS_API_URL" ] || BERGDNS_API_URL="$_BERGDNS_DEFAULT_URL"
  [ -n "$BERGDNS_TTL" ] || BERGDNS_TTL="$_BERGDNS_DEFAULT_TTL"
  [ -n "$BERGDNS_PROPAGATION_TIMEOUT" ] || BERGDNS_PROPAGATION_TIMEOUT="$_BERGDNS_DEFAULT_WAIT"

  # strip trailing slashes
  BERGDNS_API_URL=$(echo "$BERGDNS_API_URL" | sed 's#/*$##')

  _saveaccountconf_mutable BERGDNS_API_KEY "$BERGDNS_API_KEY"
  _saveaccountconf_mutable BERGDNS_API_URL "$BERGDNS_API_URL"
  _saveaccountconf_mutable BERGDNS_TTL "$BERGDNS_TTL"
  _saveaccountconf_mutable BERGDNS_PROPAGATION_TIMEOUT "$BERGDNS_PROPAGATION_TIMEOUT"
  return 0
}

# Usage: _bergdns_find_zone _acme-challenge.www.example.com
# Sets _bergdns_zone_id and _bergdns_zone_name.
# Zones are addressed by an id, not by name, so the zone list is fetched once
# and the longest matching zone name wins.
_bergdns_find_zone() {
  _fqdn=$1
  _bergdns_zone_id=""
  _bergdns_zone_name=""

  if ! _bergdns_rest GET "zones"; then
    _err "bergdns: could not list zones: $_bergdns_error"
    return 1
  fi

  # one zone object per line, so id and name stay together
  _zone_lines=$(echo "$response" | tr '{' '\n' | grep '"name":"')

  _candidate="$_fqdn"
  while [ -n "$_candidate" ]; do
    _line=$(echo "$_zone_lines" | grep -F "\"name\":\"$_candidate\"," | _head_n 1)
    if [ -n "$_line" ]; then
      _bergdns_zone_id=$(echo "$_line" | _egrep_o '"id":"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
      _bergdns_zone_name="$_candidate"
      _debug _bergdns_zone_id "$_bergdns_zone_id"
      _debug _bergdns_zone_name "$_bergdns_zone_name"
      [ -n "$_bergdns_zone_id" ] && return 0
      break
    fi
    case "$_candidate" in
    *.*) _candidate=${_candidate#*.} ;;
    *) _candidate="" ;;
    esac
  done

  _err "bergdns: no zone in this account holds $_fqdn."
  _err "bergdns: the key must be able to read the zone as well as write the record."
  return 1
}

# Usage: _bergdns_find_rrset _acme-challenge.www.example.com
# Sets _bergdns_rrset_id to the id of the TXT RRset at that name, or to an
# empty string if there is none. Records are addressed by id, so the zone's
# RRsets are listed to find it.
_bergdns_find_rrset() {
  _fqdn=$1
  _bergdns_rrset_id=""

  if ! _bergdns_rest GET "zones/$_bergdns_zone_id/rrsets"; then
    _err "bergdns: could not list the records of $_bergdns_zone_name: $_bergdns_error"
    return 1
  fi

  _line=$(echo "$response" | tr '{' '\n' | grep -F "\"name\":\"$_fqdn\",\"type\":\"TXT\"," | _head_n 1)
  if [ -n "$_line" ]; then
    _bergdns_rrset_id=$(echo "$_line" | _egrep_o '"id":"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
  fi
  _debug _bergdns_rrset_id "$_bergdns_rrset_id"
  return 0
}

# Usage: _bergdns_wait _acme-challenge.www.example.com
# Polls the propagation endpoint until all bergdns nameservers serve the
# record. A timeout is logged but does not fail the issuance.
_bergdns_wait() {
  _fqdn=$1
  if [ "$BERGDNS_PROPAGATION_TIMEOUT" = "0" ] || [ -z "$_bergdns_rrset_id" ]; then
    return 0
  fi

  _waited=0
  while [ "$_waited" -lt "$BERGDNS_PROPAGATION_TIMEOUT" ]; do
    if _bergdns_rest GET "zones/$_bergdns_zone_id/rrsets/$_bergdns_rrset_id/propagation"; then
      case "$response" in
      *'"propagated":true'*)
        _info "bergdns: $_fqdn is served by every secondary after ${_waited}s"
        return 0
        ;;
      esac
    elif [ "$_bergdns_code" = "propagation_unavailable" ]; then
      # propagation checks are not configured on this server
      _info "bergdns: this deployment does not offer propagation checks; not waiting"
      return 0
    fi
    _sleep 5
    _waited=$((_waited + 5))
  done

  _info "bergdns: $_fqdn was not on every secondary after ${BERGDNS_PROPAGATION_TIMEOUT}s; continuing anyway"
  return 0
}

# Usage: _bergdns_rest method endpoint [body]
# Sets response. On failure also sets _bergdns_error and _bergdns_code.
_bergdns_rest() {
  _method=$1
  _endpoint=$2
  _body=$3
  _bergdns_error=""
  _bergdns_code=""

  export _H1="Authorization: Bearer $BERGDNS_API_KEY"
  export _H2="Accept: application/json"

  _url="$BERGDNS_API_URL/$_endpoint"
  _debug _url "$_url"

  if [ "$_method" = "GET" ]; then
    response="$(_get "$_url")"
  else
    _debug2 _body "$_body"
    response="$(_post "$_body" "$_url" "" "$_method" "application/json")"
  fi
  _ret="$?"
  _debug2 response "$response"

  if [ "$_ret" != "0" ]; then
    _bergdns_error="the request to $_url could not be made"
    return 1
  fi

  # Errors are returned as RFC 9457 problem+json, which always has "status" and
  # "code". Successful responses have neither, so the body is checked instead
  # of the HTTP status code.
  case "$response" in
  *'"status":'*'"code":"'* | *'"code":"'*'"status":'*)
    _bergdns_error=$(echo "$response" | sed -n 's/.*"detail":"\([^"]*\)".*/\1/p')
    [ -n "$_bergdns_error" ] || _bergdns_error="$response"
    _bergdns_code=$(echo "$response" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')
    return 1
    ;;
  esac
  return 0
}
