#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_primedns_info='PrimeDNS
Site: primedns.net
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_primedns
Options:
 PRIMEDNS_API_KEY API Key. Scope acme:write:<hostname> for each name you issue (or dns:write)
'

PRIMEDNS_Api="https://api.primedns.net/v1"

########  Public functions #####################

#Usage: dns_primedns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_primedns_add() {
  fulldomain=$1
  txtvalue=$2

  PRIMEDNS_API_KEY="${PRIMEDNS_API_KEY:-$(_readaccountconf_mutable PRIMEDNS_API_KEY)}"
  if [ -z "$PRIMEDNS_API_KEY" ]; then
    PRIMEDNS_API_KEY=""
    _err "You didn't specify a PrimeDNS API key (PRIMEDNS_API_KEY) yet."
    _err "Create one in the PrimeDNS panel (Account -> API Keys) with the scope acme:write:<hostname> for each name you issue."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable PRIMEDNS_API_KEY "$PRIMEDNS_API_KEY"

  _info "Using PrimeDNS"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _primedns_rest POST "$fulldomain" "$txtvalue"; then
    return 1
  fi
  _info "Added, OK"
  return 0
}

#Usage: dns_primedns_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_primedns_rm() {
  fulldomain=$1
  txtvalue=$2

  PRIMEDNS_API_KEY="${PRIMEDNS_API_KEY:-$(_readaccountconf_mutable PRIMEDNS_API_KEY)}"
  if [ -z "$PRIMEDNS_API_KEY" ]; then
    PRIMEDNS_API_KEY=""
    _err "You didn't specify a PrimeDNS API key (PRIMEDNS_API_KEY) yet."
    return 1
  fi

  _info "Using PrimeDNS"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _primedns_rest DELETE "$fulldomain" "$txtvalue"; then
    return 1
  fi
  _info "Removed, OK"
  return 0
}

####################  Private functions below ##################################

#Usage: _primedns_rest  POST|DELETE  _acme-challenge.www.domain.com  txtvalue
#The API creates/removes the TXT record _acme-challenge.<domain> in the matching
#zone of the account (zone lookup is done server side), so the "_acme-challenge."
#prefix is cut off here and only the name being validated is sent. A name that
#does not start with "_acme-challenge." (acme.sh's own DNS API test uses one) is
#sent as it is.
_primedns_rest() {
  _method=$1
  _name=${2#_acme-challenge.}
  _value=$3

  #acme.sh sends _H1.._H5 with every later request of this process, so the API key
  #header must not stay set once this call is done (it would reach other hosts).
  _primedns_old_h1="$_H1"
  export _H1="X-API-Key: $PRIMEDNS_API_KEY"
  _body="{\"domain\":\"$_name\",\"value\":\"$_value\"}"
  _debug _body "$_body"

  if ! response="$(_post "$_body" "$PRIMEDNS_Api/dns/acme-challenge" "" "$_method" "application/json")"; then
    export _H1="$_primedns_old_h1"
    _err "Error calling the PrimeDNS API ($_method /dns/acme-challenge)."
    return 1
  fi
  export _H1="$_primedns_old_h1"
  response="$(echo "$response" | _normalizeJson)"
  _debug response "$response"

  if _contains "$response" '"success":true'; then
    return 0
  fi

  if _contains "$response" 'NAME_NOT_ALLOWED'; then
    _err "This PrimeDNS API key may not validate $_name: add the scope acme:write:$_name to the key."
  elif _contains "$response" 'INSUFFICIENT_SCOPE'; then
    _err "This PrimeDNS API key needs the scope acme:write:$_name (or dns:write)."
  elif _contains "$response" 'DOMAIN_NOT_FOUND'; then
    _err "$_name is not in a zone of the PrimeDNS account that owns this API key."
  else
    _err "PrimeDNS API error: $response"
  fi
  return 1
}
