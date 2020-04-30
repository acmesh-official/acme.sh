#!/usr/bin/env sh

TRANSIP_Token="ey..."
TRANSIP_DomainName="domain.com"

TRANSIP_Api="https://api.transip.nl/v6"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_transip_add() {
  fulldomain=$1
  txtvalue=$2

  TRANSIP_Token="${TRANSIP_Token:-$(_readaccountconf_mutable TRANSIP_Token)}"
  TRANSIP_DomainName="${TRANSIP_DomainName:-$(_readaccountconf_mutable TRANSIP_DomainName)}"

  if [ "$TRANSIP_Token" ]; then
    _saveaccountconf_mutable TRANSIP_Token "$TRANSIP_Token"
  else
    _err "You didn't specify a TransIP api access token yet."
    return 1
  fi
  if [ "$TRANSIP_DomainName" ]; then
    _saveaccountconf_mutable TRANSIP_DomainName "$TRANSIP_DomainName"
  else
    _err "You didn't specify a TransIP domainname yet."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _transip_get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain "$_domain"

  _info "Adding record"
  if _transip_rest POST "domains/$TRANSIP_DomainName/dns" "{\"dnsEntry\": {\"name\": \"$_sub_domain\",\"expire\": 300,\"type\": \"TXT\", \"content\": \"$txtvalue\"}}"; then
      _info "Added, OK"
      return 0
  fi
  _err "Add txt record error."
  return 1

}

#fulldomain txtvalue
dns_transip_rm() {
  fulldomain=$1
  txtvalue=$2

  TRANSIP_Token="${TRANSIP_Token:-$(_readaccountconf_mutable TRANSIP_Token)}"
  TRANSIP_DomainName="${TRANSIP_DomainName:-$(_readaccountconf_mutable TRANSIP_DomainName)}"

  _debug "First detect the root zone"
  if ! _transip_get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain "$_domain"

    if _transip_rest DELETE "domains/$TRANSIP_DomainName/dns" "{\"dnsEntry\": {\"name\": \"$_sub_domain\",\"expire\": 300,\"type\": \"TXT\", \"content\": \"$txtvalue\"}}"; then
      _info "Removed, OK"
      return 0
    fi

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www

_transip_get_root() {
  domain=$1
  _cutlength=$((${#domain} - ${#TRANSIP_DomainName} - 1))
  _sub_domain=$(printf "%s" "$domain" | cut -c "1-$_cutlength")
  _debug _sub_domain "$_sub_domain"
  return 0
}

_transip_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  token_trimmed=$(echo "$TRANSIP_Token" | tr -d '"')

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $token_trimmed"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$TRANSIP_Api/$ep" "" "$m")"
  else
    response="$(_get "$TRANSIP_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
