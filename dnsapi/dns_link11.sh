#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_link11_info='link11.com
Site: link11.com/
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_link11
Options:
 LINK11_API_KEY xxxx
'

LINK11_API="https://api.link11.de"
LINK11_SERVICE_KEY="l11securedns"
# Link11 API documentation https://docs.link11.com/using-link11/api/secure-dns
# How to create an API key: https://docs.link11.com/product-guides/secure-dns/interface/api-access

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_link11_add() {
  fulldomain=$1
  txtvalue=$2

  LINK11_API_KEY="${LINK11_API_KEY:-$(_readaccountconf_mutable LINK11_API_KEY)}"
  _saveaccountconf_mutable LINK11_API_KEY "$LINK11_API_KEY"

  _info "Using Link11 Secure DNS"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  if [ -z "$LINK11_API_KEY" ]; then
    _err "Missing LINK11_API_KEY environment variable."
  fi
  if ! _exists jq; then
    _err "Tool 'jq' is required but not installed."
    return 1
  fi

  _debug "First detect the root zone for $fulldomain"
  if ! _get_root "$fulldomain"; then
    _err "Failed to get root zone for $fulldomain"
    return 1
  fi
  _debug _zone_id "$_zone_id"
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  # get existing entries for the zone
  if ! _link11_rest "list_primary_zone_entries&zone=$_zone_id"; then
    _err "Failed to list primary zone entries for $_zone_id"
    return 1
  fi
  value="$(printf "%s" "$response" | jq -r --arg sub_domain "$_sub_domain" '.data[] | select(.type=="TXT" and .name==$sub_domain) | .value' | _head_n 1)"
  if [ -n "$value" ]; then
    _debug2 "Entry already exists for $_sub_domain with value $value"
    if [ "$value" = "$txtvalue" ]; then
      _info "TXT record for $fulldomain already exists with the correct value."
      return 0
    else
      _debug2 "Updating existing TXT record for $_sub_domain with new value $txtvalue"
      entry_id="$(printf "%s" "$response" | jq -r --arg sub_domain "$_sub_domain" '.data[] | select(.type=="TXT" and .name==$sub_domain) | .id' | _head_n 1)"
      _link11_rest "update_primary_zone_entry&zone=$_zone_id&entry=$entry_id&value=$txtvalue"
    fi
  else
    _debug2 "No existing entry found for $_sub_domain, adding new TXT record"
    _link11_rest "add_primary_zone_entry&zone=$_zone_id&name=$_sub_domain&value=$txtvalue&type=TXT&ttl=60"
  fi

  # validate the addition
  if ! _link11_rest "list_primary_zone_entries&zone=$_zone_id"; then
    _err "Failed to list primary zone entries for $_zone_id"
    return 1
  fi
  value="$(printf "%s" "$response" | jq -r --arg sub_domain "$_sub_domain" '.data[] | select(.type=="TXT" and .name==$sub_domain) | .value' | _head_n 1)"
  if [ -z "$value" ] || [ "$value" != "$txtvalue" ]; then
    _debug2 "Expected TXT record value for $_sub_domain is $txtvalue, but got $value"
    _err "Failed to add TXT record for $fulldomain"
    return 1
  fi
  _info "Added TXT record for $fulldomain with value $txtvalue"
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_link11_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using Link11 Secure DNS"

  _debug "First detect the root zone for $fulldomain"
  if ! _get_root "$fulldomain"; then
    _err "Failed to get root zone for $fulldomain"
    return 1
  fi
  _debug _zone_id "$_zone_id"
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  # get entry id
  if ! _link11_rest "list_primary_zone_entries&zone=$_zone_id"; then
    _err "Failed to list primary zone entries for $_zone_id"
    return 1
  fi
  entry_id="$(printf "%s" "$response" | jq -r --arg sub_domain "$_sub_domain" '.data[] | select(.type=="TXT" and .name==$sub_domain) | .id' | _head_n 1)"
  if [ -z "$entry_id" ]; then
    _info "Nothing to remove, no entry found for $_sub_domain"
    return 0
  fi
  # remove entry
  if ! _link11_rest "delete_primary_zone_entry&zone=$_zone_id&entry=$entry_id"; then
    _err "Failed to remove entry for $_sub_domain"
    return 1
  fi
  _debug2 "Removed entry for $_sub_domain"
  return 0
}

####################  Private functions below ##################################

#_acme-challenge.www.domain.com
#returns
# _zone_id=l11securednsprimary1234
# _domain=domain.com
# _sub_domain=_acme-challenge.www
_get_root() {
  domain="$1"

  _link11_rest "list_primary_zones"
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug2 h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi
    _zone_id="$(printf "%s" "$response" | jq -r --arg h "$h" '.data[] | select(.domain==$h) | .id')"
    if [ "$_zone_id" ]; then
      _sub_domain="$(printf "%s" "$domain" | cut -d . -f 1-"$p")"
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_link11_rest() {
  parameters="$1"
  _debug2 "parameters" "$parameters"

  export _H1="Content-Type: application/json"
  export _H2="key: $LINK11_API_KEY"
  response="$(_get "$LINK11_API/?apikey=$LINK11_SERVICE_KEY&$parameters")"
  # shellcheck disable=SC2181
  if [ "$?" != "0" ] || [ "$(printf "%s" "$response" | jq -r '.status_code')" != "200" ]; then
    _err "$response"
    return 1
  fi
  _debug2 "response" "$response"
  return 0
}
