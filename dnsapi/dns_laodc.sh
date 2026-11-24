#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_laodc_info='LaoDC DNS API Server
Site: laodc.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_laodc
Options:
 LaoDC_Key API Key
Issues: github.com/acmesh-official/acme.sh/issues/6973
Author: @laodc
'

# Usage:
#   export LaoDC_Key="your-api-key"
#   acme.sh --issue --dns dns_laodc -d example.la -d *.example.la --dnssleep 120
#
# The credentials will be saved in ~/.acme.sh/account.conf

LAODC_VER="0.1.2"
LAODC_API_ENDPOINT="https://dns.laodc.com/v1"

########  Public functions #####################

# Usage: dns_laodc_add  _acme-challenge.example.la  ZPXvna6tBhq7XQMH7_t2WC2sg0F-BdmtmmpUJiK6Ho
dns_laodc_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using LaoDC DNS API"

  _laodc_validate_key || return 1

  _debug "Checking root zone exists for [$fulldomain]"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  domain_hash=$(echo "$response" | _egrep_o "\"hash\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"
  _debug _domain_hash "$domain_hash"

  _info "Adding acme record"
  if _laodc_api "POST" "$domain_hash" "$_sub_domain" "$txtvalue"; then
    if [ "$_code" = "201" ]; then
      _info "Added, OK"
      return 0
    else
      _err "Add TXT record error, invalid code. Code: $_code"
      return 1
    fi
  fi

  _err "Add TXT record error."
  return 1
}

dns_laodc_rm() {
  fulldomain=$1
  txtvalue=$2

  _laodc_validate_key || return 1

  _debug "Checking root zone exists for [$fulldomain]"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  domain_hash=$(echo "$response" | _egrep_o "\"hash\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")
  _debug _root_domain "$_domain"
  _debug _sub_domain "$_sub_domain"
  _debug _domain_hash "$domain_hash"

  _info "Deleting acme record"
  if _laodc_api "DELETE" "$domain_hash" "$_sub_domain" "$txtvalue"; then
    if [ "$_code" = "204" ]; then
      _info "Deleted, OK"
      return 0
    else
      _err "Delete TXT record error, invalid code. Code: $_code"
      return 1
    fi
  fi

  _err "Delete TXT record error."
  return 1
}

####################  Private functions below ##################################
# _acme-challenge.www.domain.com
# returns
# _domain=domain.com
# _sub_domain=www
_get_root() {
  fqdn=$1
  p=1
  i=1

  while true; do
    h=$(printf "%s" "$fqdn" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      return 1 # not valid domain
    fi

    # Check API if domain exists
    if _laodc_api "GET" "$h"; then
      if [ "$_code" = "200" ]; then
        _domain="$h"

        # DNS alias mode - @ is alias for fqdn
        _sub_domain=$(printf "%s" "$fqdn" | cut -d . -f 1-"$p")
        if [ "$i" = "1" ]; then
          _sub_domain="@"
        fi

        return 0
      fi
    fi

    p="$i"
    i=$(_math "$i" + 1)
  done

  return 1
}

_laodc_validate_key() {
  LaoDC_Key="${LaoDC_Key:-$(_readaccountconf_mutable LaoDC_Key)}"

  if [ -z "$LaoDC_Key" ]; then
    LaoDC_Key=""
    _err "You didn't specify a LaoDC API Key yet."
    _err "Please export LaoDC_Key and try again."
    return 1
  fi

  # Save the api key to the account conf file.
  _saveaccountconf_mutable LaoDC_Key "$LaoDC_Key"
}

_laodc_api() {
  method=$1
  domain=$2
  subdomain=$3
  value=$4

  export _H1="Content-Type: application/json"
  export _H2="User-Agent: acme.sh/$VER laodc-dns-acme-sh/$LAODC_VER"
  export _H3="Authorization: Bearer $LaoDC_Key"

  case $method in
  GET)
    if [ -n "$subdomain" ]; then
      response="$(_get "$LAODC_API_ENDPOINT/$domain/$subdomain?type=TXT")"
    else
      response="$(_get "$LAODC_API_ENDPOINT/$domain")"
    fi
    ;;
  POST)
    # Sanitize value input
    value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
    data="{ \"type\": \"TXT\", \"value\": \"$value\", \"ttl\": \"60\" }"
    response="$(_post "$data" "$LAODC_API_ENDPOINT/$domain/$subdomain" "" "POST" "application/json")"
    ;;
  DELETE)
    # Sanitize value input
    value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
    data="{ \"type\": \"TXT\", \"value\": \"$value\" }"
    response="$(_post "$data" "$LAODC_API_ENDPOINT/$domain/$subdomain" "" "DELETE" "application/json")"
    ;;
  esac

  _ret=$?

  # Unset immediately after request to prevent leaks
  export _H1=
  export _H2=
  export _H3=

  if [ "$_ret" != "0" ]; then
    _err "Error $domain"
    return 1
  fi

  responseHeaders="$(cat "$HTTP_HEADER")"

  if echo "$responseHeaders" | grep -i "Content-Type: *application/json" >/dev/null 2>&1; then
    response="$(echo "$response" | _json_decode | _normalizeJson)"
  fi

  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"

  _debug "http response code $_code"
  _debug response "$response"
  return 0
}
