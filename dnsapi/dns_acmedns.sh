#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_acmedns_info='acme-dns Server API
 The acme-dns is a limited DNS server with RESTful API to handle ACME DNS challenges.
Site: github.com/joohoi/acme-dns
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_acmedns
Options:
 ACMEDNS_USERNAME Username. Optional.
 ACMEDNS_PASSWORD Password. Optional.
 ACMEDNS_SUBDOMAIN Subdomain. Optional.
 ACMEDNS_BASE_URL API endpoint. Default: "https://auth.acme-dns.io".
Issues: github.com/dampfklon/acme.sh
Author: Wolfgang Ebner, Sven Neubuaer
'

########  Public functions #####################

#Usage: dns_acmedns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_acmedns_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using acme-dns"
  _debug "fulldomain $fulldomain"
  _debug "txtvalue $txtvalue"

  #for compatiblity from account conf
  ACMEDNS_USERNAME="${ACMEDNS_USERNAME:-$(_readaccountconf_mutable ACMEDNS_USERNAME)}"
  _clearaccountconf_mutable ACMEDNS_USERNAME
  ACMEDNS_PASSWORD="${ACMEDNS_PASSWORD:-$(_readaccountconf_mutable ACMEDNS_PASSWORD)}"
  _clearaccountconf_mutable ACMEDNS_PASSWORD
  ACMEDNS_SUBDOMAIN="${ACMEDNS_SUBDOMAIN:-$(_readaccountconf_mutable ACMEDNS_SUBDOMAIN)}"
  _clearaccountconf_mutable ACMEDNS_SUBDOMAIN

  ACMEDNS_BASE_URL="${ACMEDNS_BASE_URL:-$(_readdomainconf ACMEDNS_BASE_URL)}"
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
    ACMEDNS_USERNAME=$(echo "$response" | sed -n 's/^{.*\"username\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _debug "received username: $ACMEDNS_USERNAME"
    ACMEDNS_PASSWORD=$(echo "$response" | sed -n 's/^{.*\"password\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _debug "received password: $ACMEDNS_PASSWORD"
    ACMEDNS_SUBDOMAIN=$(echo "$response" | sed -n 's/^{.*\"subdomain\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _debug "received subdomain: $ACMEDNS_SUBDOMAIN"
    ACMEDNS_FULLDOMAIN=$(echo "$response" | sed -n 's/^{.*\"fulldomain\":[ ]*\"\([^\"]*\)\".*}/\1/p')
    _info "##########################################################"
    _info "# Create $fulldomain CNAME $ACMEDNS_FULLDOMAIN DNS entry #"
    _info "##########################################################"
    _info "Press enter to continue... "
    read -r _
  fi

  _savedomainconf ACMEDNS_BASE_URL "$ACMEDNS_BASE_URL"
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
