#!/usr/bin/env sh
#
#Author: Wolfgang Ebner
#Report Bugs here: https://github.com/webner/acme.sh
#
########  Public functions #####################

#Usage: dns_acmedns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_acmedns_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using acme-dns"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ACMEDNS_UPDATE_URL="${ACMEDNS_UPDATE_URL:-$(_readaccountconf_mutable ACMEDNS_UPDATE_URL)}"
  ACMEDNS_USERNAME="${ACMEDNS_USERNAME:-$(_readaccountconf_mutable ACMEDNS_USERNAME)}"
  ACMEDNS_PASSWORD="${ACMEDNS_PASSWORD:-$(_readaccountconf_mutable ACMEDNS_PASSWORD)}"
  ACMEDNS_SUBDOMAIN="${ACMEDNS_SUBDOMAIN:-$(_readaccountconf_mutable ACMEDNS_SUBDOMAIN)}"

  if [ "$ACMEDNS_UPDATE_URL" = "" ]; then
    ACMEDNS_UPDATE_URL="https://auth.acme-dns.io/update"
  fi

  _saveaccountconf_mutable ACMEDNS_UPDATE_URL "$ACMEDNS_UPDATE_URL"
  _saveaccountconf_mutable ACMEDNS_USERNAME "$ACMEDNS_USERNAME"
  _saveaccountconf_mutable ACMEDNS_PASSWORD "$ACMEDNS_PASSWORD"
  _saveaccountconf_mutable ACMEDNS_SUBDOMAIN "$ACMEDNS_SUBDOMAIN"

  export _H1="X-Api-User: $ACMEDNS_USERNAME"
  export _H2="X-Api-Key: $ACMEDNS_PASSWORD"
  data="{\"subdomain\":\"$ACMEDNS_SUBDOMAIN\", \"txt\": \"$txtvalue\"}"

  _debug data "$data"
  response="$(_post "$data" "$ACMEDNS_UPDATE_URL" "" "POST")"
  _debug response "$response"

  if ! echo "$response" | grep "\"$txtvalue\"" >/dev/null; then
    _err "invalid response of acme-dns"
    return 1
  fi

}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_acmedns_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using acme-dns"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
}

####################  Private functions below ##################################
