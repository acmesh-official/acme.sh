#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_googledomains_info='Google Domains
Site: Domains.Google.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_googledomains
Options:
 GOOGLEDOMAINS_ACCESS_TOKEN API Access Token
 GOOGLEDOMAINS_ZONE Zone
Issues: github.com/acmesh-official/acme.sh/issues/4545
Author: Alex Leigh <leigh@alexleigh.me>
'

GOOGLEDOMAINS_API="https://acmedns.googleapis.com/v1/acmeChallengeSets"

######## Public functions ########

#Usage: dns_googledomains_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_googledomains_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Invoking Google Domains ACME DNS API."

  if ! _dns_googledomains_setup; then
    return 1
  fi

  zone="$(_dns_googledomains_get_zone "$fulldomain")"
  if [ -z "$zone" ]; then
    _err "Could not find a Google Domains-managed zone containing the requested domain."
    return 1
  fi

  _debug zone "$zone"
  _debug txtvalue "$txtvalue"

  _info "Adding TXT record for $fulldomain."
  if _dns_googledomains_api "$zone" ":rotateChallenges" "{\"accessToken\":\"$GOOGLEDOMAINS_ACCESS_TOKEN\",\"recordsToAdd\":[{\"fqdn\":\"$fulldomain\",\"digest\":\"$txtvalue\"}],\"keepExpiredRecords\":true}"; then
    if _contains "$response" "$txtvalue"; then
      _info "TXT record added."
      return 0
    else
      _err "Error adding TXT record."
      return 1
    fi
  fi

  _err "Error adding TXT record."
  return 1
}

#Usage: dns_googledomains_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_googledomains_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Invoking Google Domains ACME DNS API."

  if ! _dns_googledomains_setup; then
    return 1
  fi

  zone="$(_dns_googledomains_get_zone "$fulldomain")"
  if [ -z "$zone" ]; then
    _err "Could not find a Google Domains-managed domain based on request."
    return 1
  fi

  _debug zone "$zone"
  _debug txtvalue "$txtvalue"

  _info "Removing TXT record for $fulldomain."
  if _dns_googledomains_api "$zone" ":rotateChallenges" "{\"accessToken\":\"$GOOGLEDOMAINS_ACCESS_TOKEN\",\"recordsToRemove\":[{\"fqdn\":\"$fulldomain\",\"digest\":\"$txtvalue\"}],\"keepExpiredRecords\":true}"; then
    if _contains "$response" "$txtvalue"; then
      _err "Error removing TXT record."
      return 1
    else
      _info "TXT record removed."
      return 0
    fi
  fi

  _err "Error removing TXT record."
  return 1
}

######## Private functions ########

_dns_googledomains_setup() {
  if [ -n "$GOOGLEDOMAINS_SETUP_COMPLETED" ]; then
    return 0
  fi

  GOOGLEDOMAINS_ACCESS_TOKEN="${GOOGLEDOMAINS_ACCESS_TOKEN:-$(_readaccountconf_mutable GOOGLEDOMAINS_ACCESS_TOKEN)}"
  GOOGLEDOMAINS_ZONE="${GOOGLEDOMAINS_ZONE:-$(_readaccountconf_mutable GOOGLEDOMAINS_ZONE)}"

  if [ -z "$GOOGLEDOMAINS_ACCESS_TOKEN" ]; then
    GOOGLEDOMAINS_ACCESS_TOKEN=""
    _err "Google Domains access token was not specified."
    _err "Please visit Google Domains Security settings to provision an ACME DNS API access token."
    return 1
  fi

  if [ "$GOOGLEDOMAINS_ZONE" ]; then
    _savedomainconf GOOGLEDOMAINS_ACCESS_TOKEN "$GOOGLEDOMAINS_ACCESS_TOKEN"
    _savedomainconf GOOGLEDOMAINS_ZONE "$GOOGLEDOMAINS_ZONE"
  else
    _saveaccountconf_mutable GOOGLEDOMAINS_ACCESS_TOKEN "$GOOGLEDOMAINS_ACCESS_TOKEN"
    _clearaccountconf_mutable GOOGLEDOMAINS_ZONE
    _clearaccountconf GOOGLEDOMAINS_ZONE
  fi

  _debug GOOGLEDOMAINS_ACCESS_TOKEN "$GOOGLEDOMAINS_ACCESS_TOKEN"
  _debug GOOGLEDOMAINS_ZONE "$GOOGLEDOMAINS_ZONE"

  GOOGLEDOMAINS_SETUP_COMPLETED=1
  return 0
}

_dns_googledomains_get_zone() {
  domain=$1

  # Use zone directly if provided
  if [ "$GOOGLEDOMAINS_ZONE" ]; then
    if ! _dns_googledomains_api "$GOOGLEDOMAINS_ZONE"; then
      return 1
    fi

    echo "$GOOGLEDOMAINS_ZONE"
    return 0
  fi

  i=2
  while true; do
    curr=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug curr "$curr"

    if [ -z "$curr" ]; then
      return 1
    fi

    if _dns_googledomains_api "$curr"; then
      echo "$curr"
      return 0
    fi

    i=$(_math "$i" + 1)
  done

  return 1
}

_dns_googledomains_api() {
  zone=$1
  apimethod=$2
  data="$3"

  if [ -z "$data" ]; then
    response="$(_get "$GOOGLEDOMAINS_API/$zone$apimethod")"
  else
    _debug data "$data"
    export _H1="Content-Type: application/json"
    response="$(_post "$data" "$GOOGLEDOMAINS_API/$zone$apimethod")"
  fi

  _debug response "$response"

  if [ "$?" != "0" ]; then
    _err "Error"
    return 1
  fi

  if _contains "$response" "\"error\": {"; then
    return 1
  fi

  return 0
}
