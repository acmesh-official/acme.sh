#!/usr/bin/env sh
#
#       Author: Marvin Edeler
#       Report Bugs here: https://github.com/Marvo2011/acme.sh/issues/1
#	Last Edit: 17.02.2022

dns_selfhost_add() {
  fulldomain=$1
  txt=$2
  _info "Calling acme-dns on selfhost"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txt"
  _debug domain "$d"

  SELFHOSTDNS_UPDATE_URL="https://selfhost.de/cgi-bin/api.pl"

  # Get values, but don't save until we successfully validated
  SELFHOSTDNS_USERNAME="${SELFHOSTDNS_USERNAME:-$(_readaccountconf_mutable SELFHOSTDNS_USERNAME)}"
  SELFHOSTDNS_PASSWORD="${SELFHOSTDNS_PASSWORD:-$(_readaccountconf_mutable SELFHOSTDNS_PASSWORD)}"
  # These values are domain dependent, so read them from there
  SELFHOSTDNS_MAP="${SELFHOSTDNS_MAP:-$(_readdomainconf SELFHOSTDNS_MAP)}"

  if [ -z "${SELFHOSTDNS_USERNAME:-}" ] || [ -z "${SELFHOSTDNS_PASSWORD:-}" ]; then
    _err "SELFHOSTDNS_USERNAME and SELFHOSTDNS_PASSWORD must be set"
    return 1
  fi

  # get the domain entry from SELFHOSTDNS_MAP
  # only match full domains (at the beginning of the string or with a leading whitespace),
  # e.g. don't match mytest.example.com or sub.test.example.com for test.example.com
  # if the domain is defined multiple times only the last occurance will be matched
  mapEntry=$(echo "$SELFHOSTDNS_MAP" | sed -n -E "s/(^|^.*[[:space:]])($fulldomain)(:[[:digit:]]+)([:]?[[:digit:]]*)(.*)/\2\3\4/p")
  _debug mapEntry $mapEntry
  if test -z "$mapEntry"; then
    _err "SELFHOSTDNS_MAP must contain the fulldomain incl. prefix and at least one RID"
    return 1
  fi

  # get the RIDs from the map entry
  rid1=$(echo "$mapEntry" | cut -d: -f2)
  _debug rid1 $rid1
  rid2=$(echo "$mapEntry" | cut -d: -f3)
  _debug rid2 $rid2

  rid=$rid1
  # check for wildcard domain and use rid2 if set
  if _startswith "$d" '*.'; then
    _debug2 "wildcard domain"
    if ! test -z "$rid2"; then
      rid=$rid2
    fi
  fi

  _info "Trying to add $txt on selfhost for rid: $rid"

  data="?username=$SELFHOSTDNS_USERNAME&password=$SELFHOSTDNS_PASSWORD&rid=$rid&content=$txt"
  response="$(_get "$SELFHOSTDNS_UPDATE_URL$data")"

  if ! echo "$response" | grep "200 OK" >/dev/null; then
    _err "Invalid response of acme-dns for selfhost"
    return 1
  fi

  # Now that we know the values are good, save them
  _saveaccountconf_mutable SELFHOSTDNS_USERNAME "$SELFHOSTDNS_USERNAME"
  _saveaccountconf_mutable SELFHOSTDNS_PASSWORD "$SELFHOSTDNS_PASSWORD"
  # These values are domain dependent, so store them there
  _savedomainconf SELFHOSTDNS_MAP "$SELFHOSTDNS_MAP"
}

dns_selfhost_rm() {
  fulldomain=$1
  txt=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txt"
  _info "Creating and removing of records is not supported by selfhost API, will not delete anything."
}
