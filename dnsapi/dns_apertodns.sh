#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_apertodns_info='ApertoDNS
Site: www.apertodns.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_apertodns
Options:
 APERTODNS_API_KEY API Key
 APERTODNS_API_URL API URL (optional, default: https://api.apertodns.com)
Author: Andrea Ferro <support@apertodns.com>
'

APERTODNS_API_DEFAULT="https://api.apertodns.com"

########  Public functions #####################

# Usage: dns_apertodns_add _acme-challenge.myhost.apertodns.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_apertodns_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using ApertoDNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  APERTODNS_API_KEY="${APERTODNS_API_KEY:-$(_readaccountconf_mutable APERTODNS_API_KEY)}"
  APERTODNS_API_URL="${APERTODNS_API_URL:-$(_readaccountconf_mutable APERTODNS_API_URL)}"

  if [ -z "$APERTODNS_API_KEY" ]; then
    APERTODNS_API_KEY=""
    _err "You did not specify APERTODNS_API_KEY yet."
    _err "Please create your API key at https://www.apertodns.com/dashboard and try again."
    _err "e.g."
    _err "export APERTODNS_API_KEY=apertodns_live_xxxxxxxx"
    return 1
  fi

  if [ -z "$APERTODNS_API_URL" ]; then
    APERTODNS_API_URL="$APERTODNS_API_DEFAULT"
  fi

  # Save the credentials
  _saveaccountconf_mutable APERTODNS_API_KEY "$APERTODNS_API_KEY"
  if [ "$APERTODNS_API_URL" != "$APERTODNS_API_DEFAULT" ]; then
    _saveaccountconf_mutable APERTODNS_API_URL "$APERTODNS_API_URL"
  fi

  # Extract hostname and TXT name from fulldomain
  # fulldomain: _acme-challenge.myhost.apertodns.com
  # hostname: myhost.apertodns.com
  # txtname: _acme-challenge
  if ! _apertodns_parse_domain "$fulldomain"; then
    return 1
  fi

  _debug _hostname "$_hostname"
  _debug _txtname "$_txtname"

  # Build JSON payload
  _info "Adding TXT record for $_hostname"
  _body="{\"hostname\":\"$_hostname\",\"txt\":{\"name\":\"$_txtname\",\"value\":\"$txtvalue\",\"action\":\"set\"}}"

  if _apertodns_rest POST "/.well-known/apertodns/v1/update" "$_body"; then
    if _contains "$response" "\"success\":true" || _contains "$response" "\"status\":\"good\"" || _contains "$response" "\"status\":\"nochg\""; then
      _info "TXT record added successfully"
      return 0
    else
      _err "Failed to add TXT record: $response"
      return 1
    fi
  fi

  _err "Error adding TXT record"
  return 1
}

# Usage: dns_apertodns_rm _acme-challenge.myhost.apertodns.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_apertodns_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using ApertoDNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  APERTODNS_API_KEY="${APERTODNS_API_KEY:-$(_readaccountconf_mutable APERTODNS_API_KEY)}"
  APERTODNS_API_URL="${APERTODNS_API_URL:-$(_readaccountconf_mutable APERTODNS_API_URL)}"

  if [ -z "$APERTODNS_API_KEY" ]; then
    APERTODNS_API_KEY=""
    _err "You did not specify APERTODNS_API_KEY yet."
    return 1
  fi

  if [ -z "$APERTODNS_API_URL" ]; then
    APERTODNS_API_URL="$APERTODNS_API_DEFAULT"
  fi

  # Extract hostname and TXT name from fulldomain
  if ! _apertodns_parse_domain "$fulldomain"; then
    return 1
  fi

  _debug _hostname "$_hostname"
  _debug _txtname "$_txtname"

  # Build JSON payload
  _info "Removing TXT record for $_hostname"
  _body="{\"hostname\":\"$_hostname\",\"txt\":{\"name\":\"$_txtname\",\"action\":\"delete\"}}"

  if _apertodns_rest POST "/.well-known/apertodns/v1/update" "$_body"; then
    if _contains "$response" "\"success\":true" || _contains "$response" "\"status\":\"good\"" || _contains "$response" "\"status\":\"nochg\""; then
      _info "TXT record removed successfully"
      return 0
    else
      _err "Failed to remove TXT record: $response"
      return 1
    fi
  fi

  _err "Error removing TXT record"
  return 1
}

####################  Private functions below ##################################

# Parse fulldomain to extract hostname and txtname
# Input: _acme-challenge.myhost.apertodns.com
# Output: _hostname=myhost.apertodns.com, _txtname=_acme-challenge
_apertodns_parse_domain() {
  domain="$1"

  # Check if domain ends with .apertodns.com
  if ! _contains "$domain" ".apertodns.com"; then
    _err "Domain must be under apertodns.com"
    return 1
  fi

  # Extract the TXT name (first part before the hostname)
  # For _acme-challenge.myhost.apertodns.com:
  # - _txtname = _acme-challenge
  # - _hostname = myhost.apertodns.com

  # Count dots to determine structure
  # _acme-challenge.myhost.apertodns.com has 4 parts
  # myhost.apertodns.com has 3 parts

  # Get everything after the first dot
  _rest="$(printf "%s" "$domain" | cut -d . -f 2-)"

  # Check if _rest is a valid apertodns hostname (X.apertodns.com)
  if _contains "$_rest" ".apertodns.com"; then
    # The first part is the TXT name
    _txtname="$(printf "%s" "$domain" | cut -d . -f 1)"
    _hostname="$_rest"
  else
    # No subdomain prefix, use the full domain
    _txtname="_acme-challenge"
    _hostname="$domain"
  fi

  # Validate hostname format
  if [ -z "$_hostname" ] || [ -z "$_txtname" ]; then
    _err "Could not parse domain: $domain"
    return 1
  fi

  return 0
}

# REST API call
# Usage: _apertodns_rest METHOD ENDPOINT [DATA]
_apertodns_rest() {
  method="$1"
  endpoint="$2"
  data="$3"

  url="$APERTODNS_API_URL$endpoint"

  export _H1="Authorization: Bearer $APERTODNS_API_KEY"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  _debug url "$url"

  if [ "$method" = "POST" ]; then
    _secure_debug2 data "$data"
    response="$(_post "$data" "$url" "" "POST")"
  else
    response="$(_get "$url")"
  fi

  _ret="$?"
  _debug2 response "$response"

  if [ "$_ret" != "0" ]; then
    _err "API request failed"
    return 1
  fi

  return 0
}
