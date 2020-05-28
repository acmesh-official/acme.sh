#!/usr/bin/env sh

DOMENESHOP_Api_Endpoint="https://api.domeneshop.no/v0"

#####################  Public functions #####################

# Usage: dns_domeneshop_add <full domain> <txt record>
# Example: dns_domeneshop_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_domeneshop_add() {
  fulldomain=$1
  txtvalue=$2

  # Get token and secret
  DOMENESHOP_Token="${DOMENESHOP_Token:-$(_readaccountconf_mutable DOMENESHOP_Token)}"
  DOMENESHOP_Secret="${DOMENESHOP_Secret:-$(_readaccountconf_mutable DOMENESHOP_Secret)}"

  if [ -z "$DOMENESHOP_Token" ] || [ -z "$DOMENESHOP_Secret" ]; then
    DOMENESHOP_Token=""
    DOMENESHOP_Secret=""
    _err "You need to spesify a Domeneshop/Domainnameshop API Token and Secret."
    return 1
  fi

  # Save the api token and secret.
  _saveaccountconf_mutable DOMENESHOP_Token "$DOMENESHOP_Token"
  _saveaccountconf_mutable DOMENESHOP_Secret "$DOMENESHOP_Secret"

  # Get the domain name id
  if ! _get_domainid "$fulldomain"; then
    _err "Did not find domainname"
    return 1
  fi

  # Create record
  _domeneshop_rest POST "domains/$_domainid/dns" "{\"type\":\"TXT\",\"host\":\"$_sub_domain\",\"data\":\"$txtvalue\",\"ttl\":120}"
}

# Usage: dns_domeneshop_rm <full domain> <txt record>
# Example: dns_domeneshop_rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_domeneshop_rm() {
  fulldomain=$1
  txtvalue=$2

  # Get token and secret
  DOMENESHOP_Token="${DOMENESHOP_Token:-$(_readaccountconf_mutable DOMENESHOP_Token)}"
  DOMENESHOP_Secret="${DOMENESHOP_Secret:-$(_readaccountconf_mutable DOMENESHOP_Secret)}"

  if [ -z "$DOMENESHOP_Token" ] || [ -z "$DOMENESHOP_Secret" ]; then
    DOMENESHOP_Token=""
    DOMENESHOP_Secret=""
    _err "You need to spesify a Domeneshop/Domainnameshop API Token and Secret."
    return 1
  fi

  # Get the domain name id
  if ! _get_domainid "$fulldomain"; then
    _err "Did not find domainname"
    return 1
  fi

  # Find record
  if ! _get_recordid "$_domainid" "$_sub_domain" "$txtvalue"; then
    _err "Did not find dns record"
    return 1
  fi

  # Remove record
  _domeneshop_rest DELETE "domains/$_domainid/dns/$_recordid"
}

#####################  Private functions #####################

_get_domainid() {
  domain=$1

  # Get domains
  _domeneshop_rest GET "domains"

  if ! _contains "$response" "\"id\":"; then
    _err "failed to get domain names"
    return 1
  fi

  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug "h" "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"$h\"" >/dev/null; then
      # We have found the domain name.
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      _domainid=$(printf "%s" "$response" | _egrep_o "[^{]*\"domain\":\"$_domain\"[^}]*" | _egrep_o "\"id\":[0-9]+" | cut -d : -f 2)
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_get_recordid() {
  domainid=$1
  subdomain=$2
  txtvalue=$3

  # Get all dns records for the domainname
  _domeneshop_rest GET "domains/$domainid/dns"

  if ! _contains "$response" "\"id\":"; then
    _debug "No records in dns"
    return 1
  fi

  if ! _contains "$response" "\"host\":\"$subdomain\""; then
    _debug "Record does not exist"
    return 1
  fi

  # Get the id of the record in question
  _recordid=$(printf "%s" "$response" | _egrep_o "[^{]*\"host\":\"$subdomain\"[^}]*" | _egrep_o "[^{]*\"data\":\"$txtvalue\"[^}]*" | _egrep_o "\"id\":[0-9]+" | cut -d : -f 2)
  if [ -z "$_recordid" ]; then
    return 1
  fi
  return 0
}

_domeneshop_rest() {
  method=$1
  endpoint=$2
  data=$3

  credentials=$(printf "%b" "$DOMENESHOP_Token:$DOMENESHOP_Secret" | _base64)

  export _H1="Authorization: Basic $credentials"
  export _H2="Content-Type: application/json"

  if [ "$method" != "GET" ]; then
    response="$(_post "$data" "$DOMENESHOP_Api_Endpoint/$endpoint" "" "$method")"
  else
    response="$(_get "$DOMENESHOP_Api_Endpoint/$endpoint")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $endpoint"
    return 1
  fi

  return 0
}
