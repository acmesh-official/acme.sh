#!/usr/bin/env sh

FORNEX_API_URL="https://fornex.com/api/dns/domain"

########  Public functions #####################

#Usage: dns_fornex_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_fornex_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _Fornex_API; then
    return 1
  fi

  domain=$(echo "$fulldomain" | sed 's/^\*\.//')

  if ! _get_domain_id "$domain"; then
    _err "Unable to determine domain ID"
    return 1
  else
    _debug _domain_id "$_domain_id"
  fi

  _info "Adding TXT record for $fulldomain"
  # Add the TXT record
  if ! _rest POST "$domain/entry_set/" "type=TXT&host=_acme-challenge&value=$txtvalue"; then
    _err "Failed to add TXT record"
    return 1
  fi

  _info "TXT record added successfully"
  return 0
}

dns_fornex_rm() {
  fulldomain=$1

  if ! _Fornex_API; then
    return 1
  fi

  domain=$(echo "$fulldomain" | sed 's/^\*\.//')

  if ! _get_domain_id "$domain"; then
    _err "Unable to determine domain ID"
    return 1
  else
    _debug _domain_id "$_domain_id"
  fi

  _info "Removing TXT records for domain: _acme-challenge.$domain"

  txt_ids=$(curl -X GET -H "Authorization: Api-Key $FORNEX_API_KEY" "https://fornex.com/api/dns/domain/$domain/entry_set/" | jq -r '.[] | select(.type == "TXT") | .id')

  if [ -z "$txt_ids" ]; then
    _info "No TXT records found for domain: _acme-challenge.$domain"
    return 0
  fi

  for txt_id in $txt_ids; do
    _info "Removing TXT record with ID: $txt_id"
    if ! _rest DELETE "$domain/entry_set/$txt_id"; then
      _err "Failed to remove TXT record with ID: $txt_id"
    else
      _info "TXT record with ID $txt_id removed successfully"
    fi
  done

  return 0
}

####################  Private functions below ##################################

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_domain_id() {
  domain=$1

  _debug "Getting domain ID for $domain"

  if echo "$domain" | grep -q "_acme-challenge"; then
    # If yes, remove "_acme-challenge" from the domain name
    domain=$(echo "$domain" | sed 's/_acme-challenge\.//')
  fi

  if ! _rest GET "$domain/entry_set/"; then
    _err "Failed to get domain ID for $domain"
    return 1
  fi

  _domain_id="$response"
  _debug "Domain ID for $domain is $_domain_id"
  return 0
}


_Fornex_API() {
  FORNEX_API_KEY="${FORNEX_API_KEY:-$(_readaccountconf_mutable FORNEX_API_KEY)}"
  if [ -z "$FORNEX_API_KEY" ]; then
    FORNEX_API_KEY=""

    _err "You didn't specify the Fornex API key yet."
    _err "Please create your key and try again."

    return 1
  fi

  _saveaccountconf_mutable FORNEX_API_KEY "$FORNEX_API_KEY"
}

#method method action data
_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Accept: application/json"
  export _H2="Authorization: Api-Key $FORNEX_API_KEY"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    url="$FORNEX_API_URL/$ep"
    echo "curl -X $m -H 'Authorization: Api-Key $FORNEX_API_KEY' -d '$data' \"$url\""
    response="$(_post "$data" "$url" "" "$m")"
  else
    echo "curl -X GET -H 'Authorization: Api-Key $FORNEX_API_KEY' $FORNEX_API_URL/$ep"
    response="$(_get "$FORNEX_API_URL/$ep" | _normalizeJson)"
  fi

  _ret="$?"
  if [ "$_ret" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
