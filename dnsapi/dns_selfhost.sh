#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_selfhost_info='SelfHost.de
Site: SelfHost.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_selfhost
Options:
 SELFHOSTDNS_USERNAME Username
 SELFHOSTDNS_PASSWORD Password
 SELFHOSTDNS_MAP Subdomain name
Issues: github.com/acmesh-official/acme.sh/issues/4291
Author: Marvin Edeler
'

dns_selfhost_add() {
  fulldomain=$1
  txt=$2
  _info "Calling acme-dns on selfhost"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txt"

  SELFHOSTDNS_UPDATE_URL="https://selfhost.de/cgi-bin/api.pl"

  # Get values, but don't save until we successfully validated
  SELFHOSTDNS_USERNAME="${SELFHOSTDNS_USERNAME:-$(_readaccountconf_mutable SELFHOSTDNS_USERNAME)}"
  SELFHOSTDNS_PASSWORD="${SELFHOSTDNS_PASSWORD:-$(_readaccountconf_mutable SELFHOSTDNS_PASSWORD)}"
  # These values are domain dependent, so read them from there
  SELFHOSTDNS_MAP="${SELFHOSTDNS_MAP:-$(_readdomainconf SELFHOSTDNS_MAP)}"
  # Selfhost api can't dynamically add TXT record,
  # so we have to store the last used RID of the domain to support a second RID for wildcard domains
  # (format: 'fulldomainA:lastRid fulldomainB:lastRid ...')
  SELFHOSTDNS_MAP_LAST_USED_INTERNAL=$(_readdomainconf SELFHOSTDNS_MAP_LAST_USED_INTERNAL)

  if [ -z "${SELFHOSTDNS_USERNAME:-}" ] || [ -z "${SELFHOSTDNS_PASSWORD:-}" ]; then
    _err "SELFHOSTDNS_USERNAME and SELFHOSTDNS_PASSWORD must be set"
    return 1
  fi

  # get the domain entry from SELFHOSTDNS_MAP
  # only match full domains (at the beginning of the string or with a leading whitespace),
  # e.g. don't match mytest.example.com or sub.test.example.com for test.example.com
  # if the domain is defined multiple times only the last occurance will be matched
  mapEntry=$(echo "$SELFHOSTDNS_MAP" | sed -n -E "s/(^|^.*[[:space:]])($fulldomain)(:[[:digit:]]+)([:]?[[:digit:]]*)(.*)/\2\3\4/p")
  _debug2 mapEntry "$mapEntry"
  if test -z "$mapEntry"; then
    _err "SELFHOSTDNS_MAP must contain the fulldomain incl. prefix and at least one RID"
    return 1
  fi

  # get the RIDs from the map entry
  rid1=$(echo "$mapEntry" | cut -d: -f2)
  rid2=$(echo "$mapEntry" | cut -d: -f3)

  # read last used rid domain
  lastUsedRidForDomainEntry=$(echo "$SELFHOSTDNS_MAP_LAST_USED_INTERNAL" | sed -n -E "s/(^|^.*[[:space:]])($fulldomain:[[:digit:]]+)(.*)/\2/p")
  _debug2 lastUsedRidForDomainEntry "$lastUsedRidForDomainEntry"
  lastUsedRidForDomain=$(echo "$lastUsedRidForDomainEntry" | cut -d: -f2)

  rid="$rid1"
  if [ "$lastUsedRidForDomain" = "$rid" ] && ! test -z "$rid2"; then
    rid="$rid2"
  fi

  _info "Trying to add $txt on selfhost for rid: $rid"

  data="?username=$SELFHOSTDNS_USERNAME&password=$SELFHOSTDNS_PASSWORD&rid=$rid&content=$txt"
  response="$(_get "$SELFHOSTDNS_UPDATE_URL$data")"

  if ! echo "$response" | grep "200 OK" >/dev/null; then
    _err "Invalid response of acme-dns for selfhost"
    return 1
  fi

  # write last used rid domain
  newLastUsedRidForDomainEntry="$fulldomain:$rid"
  if ! test -z "$lastUsedRidForDomainEntry"; then
    # replace last used rid entry for domain
    SELFHOSTDNS_MAP_LAST_USED_INTERNAL=$(echo "$SELFHOSTDNS_MAP_LAST_USED_INTERNAL" | sed -n -E "s/$lastUsedRidForDomainEntry/$newLastUsedRidForDomainEntry/p")
  else
    # add last used rid entry for domain
    if test -z "$SELFHOSTDNS_MAP_LAST_USED_INTERNAL"; then
      SELFHOSTDNS_MAP_LAST_USED_INTERNAL="$newLastUsedRidForDomainEntry"
    else
      SELFHOSTDNS_MAP_LAST_USED_INTERNAL="$SELFHOSTDNS_MAP_LAST_USED_INTERNAL $newLastUsedRidForDomainEntry"
    fi
  fi

  # Now that we know the values are good, save them
  _saveaccountconf_mutable SELFHOSTDNS_USERNAME "$SELFHOSTDNS_USERNAME"
  _saveaccountconf_mutable SELFHOSTDNS_PASSWORD "$SELFHOSTDNS_PASSWORD"
  # These values are domain dependent, so store them there
  _savedomainconf SELFHOSTDNS_MAP "$SELFHOSTDNS_MAP"
  _savedomainconf SELFHOSTDNS_MAP_LAST_USED_INTERNAL "$SELFHOSTDNS_MAP_LAST_USED_INTERNAL"
}

dns_selfhost_rm() {
  fulldomain=$1
  txt=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txt"
  _info "Creating and removing of records is not supported by selfhost API, will not delete anything."
}
