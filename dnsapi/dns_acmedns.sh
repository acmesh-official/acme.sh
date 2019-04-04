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
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ACMEDNS_UPDATE_URL="${ACMEDNS_UPDATE_URL:-$(_readaccountconf_mutable ACMEDNS_UPDATE_URL)}"
  ACMEDNS_DOMAINS="${ACMEDNS_DOMAINS:-$(_readaccountconf_mutable ACMEDNS_DOMAINS)}"
  ACMEDNS_USERNAME="${ACMEDNS_USERNAME:-$(_readaccountconf_mutable ACMEDNS_USERNAME)}"
  ACMEDNS_PASSWORD="${ACMEDNS_PASSWORD:-$(_readaccountconf_mutable ACMEDNS_PASSWORD)}"
  ACMEDNS_SUBDOMAIN="${ACMEDNS_SUBDOMAIN:-$(_readaccountconf_mutable ACMEDNS_SUBDOMAIN)}"

  if [ "$ACMEDNS_UPDATE_URL" = "" ]; then
    ACMEDNS_UPDATE_URL="https://auth.acme-dns.io/update"
  fi

  _saveaccountconf_mutable ACMEDNS_UPDATE_URL "$ACMEDNS_UPDATE_URL"
  _saveaccountconf_mutable ACMEDNS_DOMAINS "$ACMEDNS_DOMAINS"
  _saveaccountconf_mutable ACMEDNS_USERNAME "$ACMEDNS_USERNAME"
  _saveaccountconf_mutable ACMEDNS_PASSWORD "$ACMEDNS_PASSWORD"
  _saveaccountconf_mutable ACMEDNS_SUBDOMAIN "$ACMEDNS_SUBDOMAIN"

  if [ ! -z "$ACMEDNS_DOMAINS" ]; then
    _info "Using acme-dns (multi domain mode)"
    # ensure trailing comma is present
    ACMEDNS_DOMAINS="$ACMEDNS_DOMAINS,"
    while true; do
      # get next domain name
      DOMAIN=$(cut -d ',' -f 1 <<< "$ACMEDNS_DOMAINS")

      # check if we reached the last entry
      if [ -z "$DOMAIN" ]; then
        _err "no matching acme-dns domain found"
        return 1
      fi

      # check if domain name matches our current domain
      if [[ "$fulldomain" = *"$DOMAIN" ]]; then
        # if so, extract the correct username, password and subdomain
        USERNAME=$(cut -d ',' -f 1 <<< "$ACMEDNS_USERNAME")
        PASSWORD=$(cut -d ',' -f 1 <<< "$ACMEDNS_PASSWORD")
        SUBDOMAIN=$(cut -d ',' -f 1 <<< "$ACMEDNS_SUBDOMAIN")
        break
      fi
      # take next record
      ACMEDNS_DOMAINS=$(cut -d ',' -f 2- <<< "$ACMEDNS_DOMAINS")
      ACMEDNS_USERNAME=$(cut -d ',' -f 2- <<< "$ACMEDNS_USERNAME")
      ACMEDNS_PASSWORD=$(cut -d ',' -f 2- <<< "$ACMEDNS_PASSWORD")
      ACMEDNS_SUBDOMAIN=$(cut -d ',' -f 2- <<< "$ACMEDNS_SUBDOMAIN")
    done
  else
    _info "Using acme-dns"
    USERNAME=$ACMEDNS_USERNAME
    PASSWORD=$ACMEDNS_PASSWORD
    SUBDOMAIN=$ACMEDNS_SUBDOMAIN
  fi
  
  if [ -z "$USERNAME" ] | [ -z "$PASSWORD" ] | [ -z "$SUBDOMAIN" ]; then
    _err "no matching acme-dns domain found"
    return 1
  fi

  export _H1="X-Api-User: $USERNAME"
  export _H2="X-Api-Key: $PASSWORD"
  data="{\"subdomain\":\"$SUBDOMAIN\", \"txt\": \"$txtvalue\"}"

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
