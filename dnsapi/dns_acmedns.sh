#!/usr/bin/env sh
#
#Author: Wolfgang Ebner
#Author: Sven Neubuaer
#Report Bugs here: https://github.com/dampfklon/acme.sh
#
# Usage:
# export ACMEDNS_BASE_URL="https://auth.acme-dns.io"
#
# You can optionally define an already existing account:
#
# export ACMEDNS_USERNAME="https://auth.acme-dns.io"
# export ACMEDNS_PASSWORD="https://auth.acme-dns.io"
# export ACMEDNS_SUBDOMAIN="https://auth.acme-dns.io"
#
########  Public functions #####################

#Usage: dns_acmedns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_acmedns_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using acme-dns"
  _debug "fulldomain $fulldomain"
  _debug "txtvalue $txtvalue"

  ACMEDNS_BASE_URL="${ACMEDNS_BASE_URL:-$(_readaccountconf_mutable ACMEDNS_BASE_URL)}"
  ACMEDNS_USERNAME="${ACMEDNS_USERNAME:-$(_readdomainconf ACMEDNS_USERNAME)}"
  ACMEDNS_PASSWORD="${ACMEDNS_PASSWORD:-$(_readdomainconf ACMEDNS_PASSWORD)}"
  ACMEDNS_SUBDOMAIN="${ACMEDNS_SUBDOMAIN:-$(_readdomainconf ACMEDNS_SUBDOMAIN)}"

  if [ "$ACMEDNS_BASE_URL" = "" ]; then
    ACMEDNS_BASE_URL="https://auth.acme-dns.io"
  fi

  ACMEDNS_UPDATE_URL="$ACMEDNS_BASE_URL/update"
  ACMEDNS_REGISTER_URL="$ACMEDNS_BASE_URL/register"

  if [ -z "$ACMEDNS_USERNAME" ] || [ -z "$ACMEDNS_PASSWORD" ]; then
    response="$(_post "" "$ACMEDNS_REGISTER_URL" "" "POST")"
    _debug response "$response"
    ACMEDNS_USERNAME=$(echo "$response" | sed -E 's/^\{.*?\"username\":\"([^\"]*)\".*\}/\1/g;t;d')
    _debug "received username: $ACMEDNS_USERNAME"
    ACMEDNS_PASSWORD=$(echo "$response" | sed -E 's/^\{.*?\"password\":\"([^\"]*)\".*\}/\1/g;t;d')
    _debug "received password: $ACMEDNS_PASSWORD"
    ACMEDNS_SUBDOMAIN=$(echo "$response" | sed -E 's/^\{.*?\"subdomain\":\"([^\"]*)\".*\}/\1/g;t;d')
    _debug "received subdomain: $ACMEDNS_SUBDOMAIN"
    ACMEDNS_FULLDOMAIN=$(echo "$response" | sed -E 's/^\{.*?\"fulldomain\":\"([^\"]*)\".*\}/\1/g;t;d')
    _info "##########################################################"
    _info "# Create $fulldomain CNAME $ACMEDNS_FULLDOMAIN DNS entry #"
    _info "##########################################################"
    _info "Press any key to continue... "
    read -r
  fi

  _saveaccountconf_mutable ACMEDNS_BASE_URL "$ACMEDNS_BASE_URL"
  _savedomainconf ACMEDNS_USERNAME "$ACMEDNS_USERNAME"
  _savedomainconf ACMEDNS_PASSWORD "$ACMEDNS_PASSWORD"
  _savedomainconf ACMEDNS_SUBDOMAIN "$ACMEDNS_SUBDOMAIN"

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
  _debug "fulldomain $fulldomain"
  _debug "txtvalue $txtvalue"
}

####################  Private functions below ##################################
