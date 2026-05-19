#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_laodc_info='LaoDC DNS Server
Site: laodc.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_laodc
Options:
 LaoDC_Key API Key
Issues: support+acme-sh@laodc.com
Author: @laodc
'

########  Public functions #####################

LAODC_VER="0.1.2"
LAODC_API_ENDPOINT="https://dns.laodc.com/v1"

#Usage: dns_laodc_add   _acme-challenge.www.domain.com  ZPXvna6tBhq7XQMH7_t2WC2sg0F-BdmtmmpUJiK6Ho
dns_laodc_add() {
  fulldomain=$1
  txtvalue=$2
  export txtvalue

  LaoDC_Key="${LaoDC_Key:-$(_readaccountconf_mutable LaoDC_Key)}"
  if [ -z "$LaoDC_Key" ]; then
    LaoDC_Key=""
    _err "You don't specify LaoDC API Key yet."
    _err "Please create your key and try again."
    return 1
  fi

  # Save the api key to the account conf file.
  _saveaccountconf_mutable LaoDC_Key "$LaoDC_Key"

  _debug "Checking root zone exists for [$fulldomain]"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _root_domain "$_domain"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$fulldomain"
  domain_hash=$(echo "$response" | _egrep_o "\"hash\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")

  if _laodc_api "GET" "$domain_hash" "$_sub_domain"; then
    if [ "$_code" = "200" ]; then
      _debug _response "$response"
      subdomain_hash=$(echo "$response" | _egrep_o "\"hash\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")
      if _laodc_api "PATCH" "$domain_hash" "$subdomain_hash" "$txtvalue"; then
        if [ "$_code" = "201" ]; then
          _info "Updated, OK"
          return 0
        else
          _err "Update TXT record error, invalid code. Code: $_code"
          return 1
        fi
      fi
    else
      if _laodc_api "POST" "$domain_hash" "$_sub_domain" "$txtvalue"; then
        if [ "$_code" = "201" ]; then
          _info "Added, OK"
          return 0
        else
          _err "Add TXT record error, invalid code. Code: $_code"
          return 1
        fi
      fi
    fi
  fi

  _err "Add TXT record error."
  return 1
}

dns_laodc_rm() {
  fulldomain=$1
  txtvalue=$2

  LaoDC_Key="${LaoDC_Key:-$(_readaccountconf_mutable LaoDC_Key)}"

  _debug "Checking root zone exists for [$fulldomain]"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _root_domain "$_domain"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$fulldomain"

  domain_hash=$(echo "$response" | _egrep_o "\"hash\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")

  if _laodc_api "GET" "$domain_hash" "$_sub_domain"; then
    if [ "$_code" = "200" ]; then
    
      subdomain_hash=$(echo "$response" | _egrep_o "\"hash\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")
      if _laodc_api "DELETE" "$domain_hash" "$subdomain_hash" "$txtvalue"; then
        if [ "$_code" = "204" ]; then
          _info "Deleted, OK"
          return 0
        else
          _err "Delete TXT record error, invalid code. Code: $_code"
          return 1
        fi
      fi
    fi
  fi

  _err "Delete TXT record error."
  return 1
}

####################  Private functions below ##################################
# _acme-challenge.www.domain.com
# returns
# _domain=domain.com
_get_root() {
  rdomain=$1

  i="$(echo "$rdomain" | tr '.' ' ' | wc -w)"
  i=$(_math "$i" - 1)

  while true; do
    h=$(printf "%s" "$rdomain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1 # not valid domain
    fi

    # Check API if domain exists
    if _laodc_api "GET" "$h"; then
      if [ "$_code" = "200" ]; then
        _domain="$h"
        _sub_domain="${rdomain%."$_domain"}"
        return 0
      fi
    fi

    i=$(_math "$i" - 1)
    if [ "$i" -lt 2 ]; then
      return 1 #not found, no need to check _acme-challenge.sub.domain in leaseweb api.
    fi
  done

  return 1
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
        response="$(_get "$LAODC_API_ENDPOINT/$domain/$subdomain")"
      else
        response="$(_get "$LAODC_API_ENDPOINT/$domain")"
      fi
      responseHeaders="$(cat "$HTTP_HEADER")"

      if echo "$responseHeaders" | grep -i "Content-Type: *application/json" >/dev/null 2>&1; then
        response="$(echo "$response" | _json_decode | _normalizeJson)"
      fi

      _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
      _debug "http response code $_code"
      _debug response "$response"
      return 0
      ;;
    POST)
      data="{ \"type\": \"TXT\", \"value\": \"$value\", \"ttl\": \"60\" }"
      response="$(_post "$data" "$LAODC_API_ENDPOINT/$domain/$subdomain" "" "POST" "application/json")"
      responseHeaders="$(cat "$HTTP_HEADER")"

      if echo "$responseHeaders" | grep -i "Content-Type: *application/json" >/dev/null 2>&1; then
        response="$(echo "$response" | _json_decode | _normalizeJson)"
      fi

      _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
      _debug "http response code $_code"
      _debug response "$response"
      return 0
      ;;
    PATCH)
      data="{ \"type\": \"TXT\", \"value\": \"$value\", \"ttl\": \"60\" }"
      response="$(_post "$data" "$LAODC_API_ENDPOINT/$domain/$subdomain" "" "PATCH" "application/json")"
      responseHeaders="$(cat "$HTTP_HEADER")"

      if echo "$responseHeaders" | grep -i "Content-Type: *application/json" >/dev/null 2>&1; then
        response="$(echo "$response" | _json_decode | _normalizeJson)"
      fi

      _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
      _debug "http response code $_code"
      _debug response "$response"
      return 0
      ;;
    DELETE)
      data="{ \"type\": \"TXT\" }"
      response="$(_post "$data" "$LAODC_API_ENDPOINT/$domain/$subdomain" "" "DELETE" "application/json")"
      responseHeaders="$(cat "$HTTP_HEADER")"

      if echo "$responseHeaders" | grep -i "Content-Type: *application/json" >/dev/null 2>&1; then
        response="$(echo "$response" | _json_decode | _normalizeJson)"
      fi

      _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
      _debug "http response code $_code"
      _debug response "$response"
      return 0
      ;;
  esac

  return 1
}
