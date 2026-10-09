#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_selfhost_info='SelfHost.de
Site: SelfHost.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_selfhost
Options:
 SELFHOSTDNS_APIKEY API key
 SELFHOSTDNS_MAP Subdomain name
 SELFHOSTDNS_UPDATE_URL API url. Optional. Default "https://my.selfhost.de/cgi-bin/dns-api.pl"
Issues: github.com/acmesh-official/acme.sh/issues/4291
Author: Marvin Edeler
'

DEFAULT_SELFHOSTDNS_UPDATE_URL="https://my.selfhost.de/cgi-bin/dns-api.pl"

dns_selfhost_add() {
  fulldomain=$1
  txt=$2
  _info "Calling acme-dns on selfhost"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txt"

  # Get values, but don't save until we successfully validated
  if ! _selfhost_load_conf; then
    return 1
  fi
  # Selfhost api can't dynamically add TXT record,
  # so we have to store the last used RID of the domain to support a second RID for wildcard domains
  # (format: 'fulldomainA:lastRid fulldomainB:lastRid ...')
  SELFHOSTDNS_MAP_LAST_USED_INTERNAL=$(_readdomainconf SELFHOSTDNS_MAP_LAST_USED_INTERNAL)

  # read last used rid domain
  lastUsedRidForDomainEntry=$(echo "$SELFHOSTDNS_MAP_LAST_USED_INTERNAL" | sed 's/^/ /' | sed -n "s/.*[ $_selfhost_tab]\($fulldomain:[0-9][0-9]*\).*/\1/p")
  _debug2 lastUsedRidForDomainEntry "$lastUsedRidForDomainEntry"
  lastUsedRidForDomain=$(echo "$lastUsedRidForDomainEntry" | cut -d: -f2)

  rid="$rid1"
  if [ "$lastUsedRidForDomain" = "$rid" ] && ! test -z "$rid2"; then
    rid="$rid2"
  fi

  _info "Trying to add $txt on selfhost for rid: $rid"

  if ! _selfhost_api "present" "$rid" "$txt"; then
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

  # Save api url if different from default
  if [ "$DEFAULT_SELFHOSTDNS_UPDATE_URL" != "$SELFHOSTDNS_UPDATE_URL" ]; then
    _saveaccountconf_mutable SELFHOSTDNS_UPDATE_URL "$SELFHOSTDNS_UPDATE_URL"
  fi

  # Now that we know the values are good, save them
  _saveaccountconf_mutable SELFHOSTDNS_APIKEY "$SELFHOSTDNS_APIKEY"
  # The old api credentials are not used anymore
  _clearaccountconf_mutable SELFHOSTDNS_USERNAME
  _clearaccountconf_mutable SELFHOSTDNS_PASSWORD
  # These values are domain dependent, so store them there
  _savedomainconf SELFHOSTDNS_MAP "$SELFHOSTDNS_MAP"
  _savedomainconf SELFHOSTDNS_MAP_LAST_USED_INTERNAL "$SELFHOSTDNS_MAP_LAST_USED_INTERNAL"
  # remember which RID holds this txt value, so it can be cleaned up later
  # (format: 'ridA:txtA ridB:txtB ...')
  SELFHOSTDNS_TXT_RID_INTERNAL=$(_readdomainconf SELFHOSTDNS_TXT_RID_INTERNAL)
  if test -z "$SELFHOSTDNS_TXT_RID_INTERNAL"; then
    SELFHOSTDNS_TXT_RID_INTERNAL="$rid:$txt"
  else
    SELFHOSTDNS_TXT_RID_INTERNAL="$SELFHOSTDNS_TXT_RID_INTERNAL $rid:$txt"
  fi
  _savedomainconf SELFHOSTDNS_TXT_RID_INTERNAL "$SELFHOSTDNS_TXT_RID_INTERNAL"
}

dns_selfhost_rm() {
  fulldomain=$1
  txt=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txt"

  if ! _selfhost_load_conf; then
    return 1
  fi

  # find the RID which was used for this txt value
  SELFHOSTDNS_TXT_RID_INTERNAL=$(_readdomainconf SELFHOSTDNS_TXT_RID_INTERNAL)
  rids=""
  remainingTxtRidEntries=""
  for txtRidEntry in $SELFHOSTDNS_TXT_RID_INTERNAL; do
    if [ "${txtRidEntry#*:}" = "$txt" ]; then
      rids="${txtRidEntry%%:*}"
    elif test -z "$remainingTxtRidEntries"; then
      remainingTxtRidEntries="$txtRidEntry"
    else
      remainingTxtRidEntries="$remainingTxtRidEntries $txtRidEntry"
    fi
  done
  if test -z "$rids"; then
    # unknown txt value, so try all RIDs of the domain
    rids="$rid1 $rid2"
  fi

  for rid in $rids; do
    _info "Trying to remove $txt on selfhost for rid: $rid"
    if ! _selfhost_api "cleanup" "$rid" "$txt"; then
      return 1
    fi
  done

  _savedomainconf SELFHOSTDNS_TXT_RID_INTERNAL "$remainingTxtRidEntries"
}

####################  Private functions below ##################################

# reads the config and sets rid1 and rid2 for $fulldomain
_selfhost_load_conf() {
  SELFHOSTDNS_UPDATE_URL="${SELFHOSTDNS_UPDATE_URL:-$(_readaccountconf_mutable SELFHOSTDNS_UPDATE_URL)}"
  SELFHOSTDNS_UPDATE_URL="${SELFHOSTDNS_UPDATE_URL:-$DEFAULT_SELFHOSTDNS_UPDATE_URL}"
  SELFHOSTDNS_APIKEY="${SELFHOSTDNS_APIKEY:-$(_readaccountconf_mutable SELFHOSTDNS_APIKEY)}"
  # These values are domain dependent, so read them from there
  SELFHOSTDNS_MAP="${SELFHOSTDNS_MAP:-$(_readdomainconf SELFHOSTDNS_MAP)}"

  if [ -z "${SELFHOSTDNS_APIKEY:-}" ]; then
    _err "SELFHOSTDNS_APIKEY must be set"
    return 1
  fi

  # get the domain entry from SELFHOSTDNS_MAP
  # only match full domains (at the beginning of the string or with a leading whitespace),
  # e.g. don't match mytest.example.com or sub.test.example.com for test.example.com
  # if the domain is defined multiple times only the last occurance will be matched
  # prepend a space to each line so "start of line" and "after whitespace"
  # can both be matched as "after a space/tab" (portable BRE, no ERE (^|..))
  _selfhost_tab="$(printf '\t')"
  mapEntry=$(echo "$SELFHOSTDNS_MAP" | sed 's/^/ /' | sed -n "s/.*[ $_selfhost_tab]\($fulldomain:[0-9][0-9]*:\{0,1\}[0-9]*\).*/\1/p")
  _debug2 mapEntry "$mapEntry"
  if test -z "$mapEntry"; then
    _err "SELFHOSTDNS_MAP must contain the fulldomain incl. prefix and at least one RID"
    return 1
  fi

  # get the RIDs from the map entry
  rid1=$(echo "$mapEntry" | cut -d: -f2)
  rid2=$(echo "$mapEntry" | cut -d: -f3)
}

# usage: _selfhost_api action rid txt
_selfhost_api() {
  data="{\"api_key\":\"$SELFHOSTDNS_APIKEY\",\"action\":\"$1\",\"record_id\":$2,\"content\":\"$3\"}"
  response="$(_post "$data" "$SELFHOSTDNS_UPDATE_URL" "" "POST" "application/json")"
  _debug2 response "$response"

  if ! echo "$response" | grep '"ok" *: *1' >/dev/null; then
    _err "Invalid response of acme-dns for selfhost: $response"
    return 1
  fi
}
