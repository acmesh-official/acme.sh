#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_primedns_info='PrimeDNS
Site: primedns.net
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_primedns
Options:
 PRIMEDNS_API_KEY API Key. Scope acme:write:<hostname> for each name you issue (or dns:write)
OptionsAlt:
 PRIMEDNS_API_URL API base URL. Optional, default https://api.primedns.net/v1
'

PRIMEDNS_Api_Default="https://api.primedns.net/v1"

########  Public functions #####################

#Usage: dns_primedns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_primedns_add() {
  fulldomain=$(_idn "$1")
  txtvalue=$2

  PRIMEDNS_API_KEY="${PRIMEDNS_API_KEY:-$(_readaccountconf_mutable PRIMEDNS_API_KEY)}"
  if [ -z "$PRIMEDNS_API_KEY" ]; then
    PRIMEDNS_API_KEY=""
    _err "You didn't specify a PrimeDNS API key (PRIMEDNS_API_KEY) yet."
    _err "Create one in the PrimeDNS panel (Account -> API Keys) with the scope acme:write:<hostname> for each name you issue."
    return 1
  fi

  PRIMEDNS_API_URL="${PRIMEDNS_API_URL:-$(_readaccountconf_mutable PRIMEDNS_API_URL)}"

  #save the credentials to the account conf file.
  _saveaccountconf_mutable PRIMEDNS_API_KEY "$PRIMEDNS_API_KEY"
  if [ "$PRIMEDNS_API_URL" ]; then
    _saveaccountconf_mutable PRIMEDNS_API_URL "$PRIMEDNS_API_URL"
  fi

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
  fulldomain=$(_idn "$1")
  txtvalue=$2

  PRIMEDNS_API_KEY="${PRIMEDNS_API_KEY:-$(_readaccountconf_mutable PRIMEDNS_API_KEY)}"
  if [ -z "$PRIMEDNS_API_KEY" ]; then
    PRIMEDNS_API_KEY=""
    _err "You didn't specify a PrimeDNS API key (PRIMEDNS_API_KEY) yet."
    return 1
  fi
  PRIMEDNS_API_URL="${PRIMEDNS_API_URL:-$(_readaccountconf_mutable PRIMEDNS_API_URL)}"

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
  _url="${PRIMEDNS_API_URL:-$PRIMEDNS_Api_Default}/dns/acme-challenge"

  #The body is built by hand, so refuse anything that would need JSON escaping.
  case "$_name$_value" in
  *\"* | *\\*)
    _err "Refusing to send '$_name': it contains a quote or a backslash."
    return 1
    ;;
  esac
  if [ -z "$_name" ] || _is_idn "$_name"; then
    _err "Cannot send '$_name': it is not a plain ASCII host name. For an IDN name install idn (acme.sh converts it to punycode) or pass the punycode name."
    return 1
  fi
  _body="{\"domain\":\"$_name\",\"value\":\"$_value\"}"
  _debug _body "$_body"

  _primedns_retried=""
  while true; do
    #acme.sh sends _H1.._H5 with every later request of this process, so the API key
    #header must not stay set once this call is done (it would reach other hosts).
    _primedns_old_h1="$_H1"
    export _H1="X-API-Key: $PRIMEDNS_API_KEY"
    : >"$HTTP_HEADER"
    response="$(_post "$_body" "$_url" "" "$_method" "application/json")"
    _ret=$?
    export _H1="$_primedns_old_h1"
    _status=$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d '\r\n')
    if [ "$_ret" != "0" ]; then
      _err "Error calling the PrimeDNS API ($_method /dns/acme-challenge)."
      return 1
    fi
    response="$(echo "$response" | _normalizeJson)"
    _debug response "$response"
    _debug _status "$_status"

    #Rate limited or temporary server error: wait and try once more.
    if [ -z "$_primedns_retried" ] && { [ "$_status" = "429" ] || [ "$_status" = "502" ] || [ "$_status" = "503" ] || [ "$_status" = "504" ]; }; then
      _wait=$(grep -i "^Retry-After" "$HTTP_HEADER" | _tail_n 1 | cut -d : -f 2 | tr -d ' \r\n')
      case "$_wait" in
      '' | *[!0-9]*) _wait=5 ;;
      esac
      [ "$_wait" -gt 60 ] && _wait=60
      _info "PrimeDNS API answered HTTP $_status, retrying in $_wait seconds."
      _sleep "$_wait"
      _primedns_retried=1
      continue
    fi
    break
  done

  if _contains "$response" '"success":true'; then
    return 0
  fi

  if [ "$_status" = "401" ]; then
    _err "The PrimeDNS API refused the key (HTTP 401): it is wrong, revoked or expired. Check PRIMEDNS_API_KEY."
  elif _contains "$response" 'IP_NOT_ALLOWED'; then
    _err "This PrimeDNS API key may not be used from this address (allowed_ips). Add the address to the key or run acme.sh from an allowed host."
  elif _contains "$response" 'NAME_NOT_ALLOWED'; then
    _err "This PrimeDNS API key may not validate $_name: add the scope acme:write:$_name to the key, or the zone to its allowed zones."
  elif _contains "$response" 'INSUFFICIENT_SCOPE'; then
    _err "This PrimeDNS API key needs the scope acme:write:$_name (or dns:write)."
  elif _contains "$response" 'DOMAIN_NOT_FOUND'; then
    _err "$_name is not in a zone of the PrimeDNS account that owns this API key."
  elif [ "$_status" = "429" ]; then
    _err "PrimeDNS API rate limit still hit after a retry. Try again in a minute."
  else
    _err "PrimeDNS API error (HTTP $_status): $response"
  fi
  return 1
}
