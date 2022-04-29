#!/usr/bin/env sh
#
#       Author: Marvin Edeler
#       Report Bugs here: https://github.com/Marvo2011/acme.sh/issues/1
#	Last Edit: 17.02.2022

dns_selfhost_add() {
  domain=$1
  txt=$2
  _info "Calling acme-dns on selfhost"
  _debug fulldomain "$domain"
  _debug txtvalue "$txt"

  SELFHOSTDNS_UPDATE_URL="https://selfhost.de/cgi-bin/api.pl"

  # Get values, but don't save until we successfully validated
  SELFHOSTDNS_USERNAME="${SELFHOSTDNS_USERNAME:-$(_readaccountconf_mutable SELFHOSTDNS_USERNAME)}"
  SELFHOSTDNS_PASSWORD="${SELFHOSTDNS_PASSWORD:-$(_readaccountconf_mutable SELFHOSTDNS_PASSWORD)}"
  # These values are domain dependent, so read them from there
  _getdeployconf SELFHOSTDNS_MAP
  _getdeployconf SELFHOSTDNS_RID
  _getdeployconf SELFHOSTDNS_RID2
  _getdeployconf SELFHOSTDNS_LAST_SLOT

  if [ -z "${SELFHOSTDNS_USERNAME:-}" ] || [ -z "${SELFHOSTDNS_PASSWORD:-}" ]; then
    _err "SELFHOSTDNS_USERNAME and SELFHOSTDNS_PASSWORD must be set"
    return 1
  fi

  if test -z "$SELFHOSTDNS_LAST_SLOT"; then
    SELFHOSTDNS_LAST_SLOT=1
  fi

  rid=$(echo "$SELFHOSTDNS_MAP" | grep -Eoi "$domain:(\d+)" | tr -d "$domain:")

  if test -z "$rid"; then
    if [ $SELFHOSTDNS_LAST_SLOT = "2" ]; then
      rid=$SELFHOSTDNS_RID
      SELFHOSTDNS_LAST_SLOT=1
    else
      rid=$SELFHOSTDNS_RID2
      SELFHOSTDNS_LAST_SLOT=2
    fi
  fi

  if test -z "$rid"; then
    _err "SELFHOSTDNS_RID and SELFHOSTDNS_RID2, or SELFHOSTDNS_MAP must be set"
    return 1
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
  _savedeployconf SELFHOSTDNS_MAP "$SELFHOSTDNS_MAP"
  _savedeployconf SELFHOSTDNS_RID "$SELFHOSTDNS_RID"
  _savedeployconf SELFHOSTDNS_RID2 "$SELFHOSTDNS_RID2"
  _savedeployconf SELFHOSTDNS_LAST_SLOT "$SELFHOSTDNS_LAST_SLOT"
}

dns_selfhost_rm() {
  domain=$1
  txt=$2
  _debug fulldomain "$domain"
  _debug txtvalue "$txt"
  _info "Creating and removing of records is not supported by selfhost API, will not delete anything."
}
