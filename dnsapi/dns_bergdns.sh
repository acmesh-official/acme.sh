#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_bergdns_info='bergdns.at
Site: bergdns.at
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_bergdns
Options:
 BERGDNS_API_KEY API key, as issued in the account UI. Needs read (to find the zone and the record) and write over the challenge names.
 BERGDNS_API_URL API base URL. Optional. Default "https://bergdns.at/v1".
 BERGDNS_TTL TTL of the challenge record, in seconds. Optional. Default "60".
 BERGDNS_PROPAGATION_TIMEOUT Seconds to wait for the record to reach every secondary. Optional. Default "60". "0" does not wait.
Issues: github.com/acmesh-official/acme.sh/issues/7261
Author: Kenny Kropp <https://github.com/kekropp>
'

_BERGDNS_DEFAULT_URL='https://bergdns.at/v1'
_BERGDNS_DEFAULT_TTL='60'
_BERGDNS_DEFAULT_WAIT='60'

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
      _debug _bergdns_rrset_id "$_bergdns_rrset_id"
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
    # Any flavour of not-found is a cleanup that has already happened: the
    # RRset was removed by a previous run, or by the other half of a
    # domain-and-wildcard pair taking the last value with it.
    if [ "$_bergdns_status" = "404" ]; then
      _info "bergdns: $fulldomain holds no such record any more, nothing to remove"
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

  # The TTL is interpolated into the request body and the timeout is counted
  # down in arithmetic, so a stray value from the environment or from an old
  # account.conf has to be caught here rather than become malformed JSON and
  # an opaque 400.
  case "$BERGDNS_TTL" in
  *[!0-9]* | '')
    _err "bergdns: BERGDNS_TTL must be a number of seconds, not \"$BERGDNS_TTL\"."
    return 1
    ;;
  esac
  case "$BERGDNS_PROPAGATION_TIMEOUT" in
  *[!0-9]* | '')
    _err "bergdns: BERGDNS_PROPAGATION_TIMEOUT must be a number of seconds, not \"$BERGDNS_PROPAGATION_TIMEOUT\"."
    return 1
    ;;
  esac

  _saveaccountconf_mutable BERGDNS_API_KEY "$BERGDNS_API_KEY"
  # Only what the user actually chose is written back, and a value equal to
  # the default clears any older setting. Persisting a default would pin the
  # install to today's value, and a later change to the shipped one -- a move
  # of the API base above all -- would never reach it; leaving an old setting
  # in place would mean the environment could never put one back to default.
  if [ "$BERGDNS_API_URL" = "$_BERGDNS_DEFAULT_URL" ]; then
    _clearaccountconf_mutable BERGDNS_API_URL
  else
    _saveaccountconf_mutable BERGDNS_API_URL "$BERGDNS_API_URL"
  fi
  if [ "$BERGDNS_TTL" = "$_BERGDNS_DEFAULT_TTL" ]; then
    _clearaccountconf_mutable BERGDNS_TTL
  else
    _saveaccountconf_mutable BERGDNS_TTL "$BERGDNS_TTL"
  fi
  if [ "$BERGDNS_PROPAGATION_TIMEOUT" = "$_BERGDNS_DEFAULT_WAIT" ]; then
    _clearaccountconf_mutable BERGDNS_PROPAGATION_TIMEOUT
  else
    _saveaccountconf_mutable BERGDNS_PROPAGATION_TIMEOUT "$BERGDNS_PROPAGATION_TIMEOUT"
  fi
  return 0
}

# Usage: _bergdns_find_zone _acme-challenge.www.example.com
# Sets _bergdns_zone_id and _bergdns_zone_name.
# Zones are addressed by an id, not by name, so the zone list is fetched once
# and the longest matching zone name wins.
_bergdns_find_zone() {
  _bergdns_fqdn=$1
  _bergdns_zone_id=""
  _bergdns_zone_name=""

  if ! _bergdns_rest GET "zones"; then
    _err "bergdns: could not list zones: $_bergdns_error"
    return 1
  fi

  # one zone object per line, so id and name stay together
  _bergdns_zone_lines=$(echo "$response" | tr '{' '\n')

  _bergdns_cand="$_bergdns_fqdn"
  while [ -n "$_bergdns_cand" ]; do
    _bergdns_line=$(echo "$_bergdns_zone_lines" | _bergdns_select "$_bergdns_cand" | _head_n 1)
    if [ -n "$_bergdns_line" ]; then
      _bergdns_zone_id=$(echo "$_bergdns_line" | _egrep_o '"id":"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
      _bergdns_zone_name="$_bergdns_cand"
      _debug _bergdns_zone_id "$_bergdns_zone_id"
      _debug _bergdns_zone_name "$_bergdns_zone_name"
      [ -n "$_bergdns_zone_id" ] && return 0
      break
    fi
    case "$_bergdns_cand" in
    *.*) _bergdns_cand=${_bergdns_cand#*.} ;;
    *) _bergdns_cand="" ;;
    esac
  done

  _err "bergdns: no zone in this account holds $_bergdns_fqdn."
  _err "bergdns: the key must be able to read the zone as well as write the record."
  return 1
}

# Usage: _bergdns_find_rrset _acme-challenge.www.example.com
# Sets _bergdns_rrset_id to the id of the TXT RRset at that name, or to an
# empty string if there is none. Records are addressed by id, so the zone's
# RRsets are listed to find it.
_bergdns_find_rrset() {
  _bergdns_fqdn=$1
  _bergdns_rrset_id=""

  if ! _bergdns_rest GET "zones/$_bergdns_zone_id/rrsets"; then
    _err "bergdns: could not list the records of $_bergdns_zone_name: $_bergdns_error"
    return 1
  fi

  _bergdns_line=$(echo "$response" | tr '{' '\n' | _bergdns_select "$_bergdns_fqdn" TXT | _head_n 1)
  if [ -n "$_bergdns_line" ]; then
    _bergdns_rrset_id=$(echo "$_bergdns_line" | _egrep_o '"id":"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
  fi
  _debug _bergdns_rrset_id "$_bergdns_rrset_id"
  return 0
}

# Usage: ... | _bergdns_select name [type]
# Reads one JSON object per line and prints those whose "name" is name and,
# when a type is given, whose "type" is that type. The two fields are matched
# one at a time, so neither the order the server writes its keys in nor
# anything sitting between them changes the answer.
#
# The comparison is a shell case, which is literal by construction: grep -F
# does not exist on Solaris, and _contains and _startswith would read the name
# as a regular expression. Each pattern anchors on the start of the object or
# on the comma before the key, so a key that merely ends in "name" cannot
# match.
_bergdns_select() {
  _bergdns_sel_name=$1
  _bergdns_sel_type=$2
  while IFS= read -r _bergdns_sel_line || [ -n "$_bergdns_sel_line" ]; do
    case "$_bergdns_sel_line" in
    '"name":"'"$_bergdns_sel_name"'"'* | *',"name":"'"$_bergdns_sel_name"'"'*) ;;
    *) continue ;;
    esac
    if [ -n "$_bergdns_sel_type" ]; then
      case "$_bergdns_sel_line" in
      '"type":"'"$_bergdns_sel_type"'"'* | *',"type":"'"$_bergdns_sel_type"'"'*) ;;
      *) continue ;;
      esac
    fi
    printf '%s\n' "$_bergdns_sel_line"
  done
}

# Usage: _bergdns_wait _acme-challenge.www.example.com
# Polls the propagation endpoint until all bergdns nameservers serve the
# record. A timeout is logged but does not fail the issuance.
#
# This covers the zone transfer from the primary to the secondaries, which
# takes seconds; the resolver side is acme.sh's own _check_dns_entries, which
# runs after every record has been added and has a timeout of its own.
_bergdns_wait() {
  _bergdns_fqdn=$1
  if [ "$BERGDNS_PROPAGATION_TIMEOUT" = "0" ] || [ -z "$_bergdns_rrset_id" ]; then
    return 0
  fi

  _bergdns_waited=0
  while [ "$_bergdns_waited" -lt "$BERGDNS_PROPAGATION_TIMEOUT" ]; do
    if _bergdns_rest GET "zones/$_bergdns_zone_id/rrsets/$_bergdns_rrset_id/propagation"; then
      case "$response" in
      *'"propagated":true'*)
        _info "bergdns: $_bergdns_fqdn is served by every secondary after ${_bergdns_waited}s"
        return 0
        ;;
      esac
    elif [ "$_bergdns_code" = "propagation_unavailable" ]; then
      # propagation checks are not configured on this server
      _info "bergdns: this deployment does not offer propagation checks; not waiting"
      return 0
    else
      case "$_bergdns_status" in
      429) ;; # rate limited, worth another go
      4*)
        # The check is refused rather than pending, and waiting will not
        # change that. _check_dns_entries still has to pass, so this is not
        # the place to fail the issuance.
        _info "bergdns: the propagation check is unavailable ($_bergdns_error); not waiting"
        return 0
        ;;
      esac
    fi
    _sleep 5
    _bergdns_waited=$((_bergdns_waited + 5))
  done

  _info "bergdns: $_bergdns_fqdn was not on every secondary after ${BERGDNS_PROPAGATION_TIMEOUT}s; continuing anyway"
  return 0
}

# Usage: _bergdns_rest method endpoint [body]
# Sets response and _bergdns_status. On failure also sets _bergdns_error and,
# where the API itself answered, _bergdns_code.
_bergdns_rest() {
  _bergdns_method=$1
  _bergdns_endpoint=$2
  _bergdns_body=$3
  _bergdns_error=""
  _bergdns_code=""
  _bergdns_status=""

  export _H1="Authorization: Bearer $BERGDNS_API_KEY"
  export _H2="Accept: application/json"

  _bergdns_url="$BERGDNS_API_URL/$_bergdns_endpoint"
  _debug _bergdns_url "$_bergdns_url"

  # drop the headers of the previous request, so that a request which never
  # reaches the server cannot be read as carrying its status
  if [ -f "$HTTP_HEADER" ]; then
    : >"$HTTP_HEADER"
  fi

  if [ "$_bergdns_method" = "GET" ]; then
    response="$(_get "$_bergdns_url")"
  else
    _debug2 _bergdns_body "$_bergdns_body"
    response="$(_post "$_bergdns_body" "$_bergdns_url" "" "$_bergdns_method" "application/json")"
  fi
  _bergdns_ret="$?"
  _debug2 response "$response"

  if [ "$_bergdns_ret" != "0" ]; then
    _bergdns_error="the request to $_bergdns_url could not be made"
    return 1
  fi

  _bergdns_status="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
  _debug _bergdns_status "$_bergdns_status"

  # The HTTP status decides. Errors from the API itself are RFC 9457
  # problem+json and carry a "detail" to show and a stable "code" to branch on,
  # but a request that never gets that far -- bergdns.at answers from behind a
  # reverse proxy, whose 502 and 504 are HTML -- has neither, and reading the
  # body alone would take those for success.
  case "$_bergdns_status" in
  2*) return 0 ;;
  esac
  _bergdns_error=$(echo "$response" | _egrep_o '"detail":"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
  _bergdns_code=$(echo "$response" | _egrep_o '"code":"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
  [ -n "$_bergdns_error" ] || _bergdns_error="$_bergdns_url answered HTTP ${_bergdns_status:-(none)}"
  _debug _bergdns_code "$_bergdns_code"
  return 1
}
