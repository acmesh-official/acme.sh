#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_eurodns_info='EuroDNS
Site: eurodns.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_eurodns
Options:
 EURODNS_APP_ID Application ID
 EURODNS_API_KEY API Key
 EURODNS_TTL TTL. Default: "600".
Issues: github.com/acmesh-official/acme.sh/issues
Author: Nicolas Santorelli
'

#
# EuroDNS DNS API
#
# EuroDNS API documentation:
# https://docapi.eurodns.com
#
# Usage:
#   export EURODNS_APP_ID="your-app-id"
#   export EURODNS_API_KEY="your-api-key"
#   acme.sh --issue --dns dns_eurodns -d example.com -d *.example.com
#
# The credentials will be saved in ~/.acme.sh/account.conf
#
# Optional:
#   export EURODNS_API_URL="https://rest-api.eurodns.com"  # Default API URL
#   export EURODNS_TTL=600  # Default TTL (minimum 600 for EuroDNS)
#

EURODNS_API_DEFAULT="https://rest-api.eurodns.com"
EURODNS_TTL_DEFAULT=600

########  Public functions #####################

#Usage: dns_eurodns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_eurodns_add() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  _info "Using EuroDNS DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  EURODNS_APP_ID="${EURODNS_APP_ID:-$(_readaccountconf_mutable EURODNS_APP_ID)}"
  EURODNS_API_KEY="${EURODNS_API_KEY:-$(_readaccountconf_mutable EURODNS_API_KEY)}"
  EURODNS_API_URL="${EURODNS_API_URL:-$(_readaccountconf_mutable EURODNS_API_URL)}"
  EURODNS_API_URL="${EURODNS_API_URL:-$EURODNS_API_DEFAULT}"
  EURODNS_TTL="${EURODNS_TTL:-$(_readaccountconf_mutable EURODNS_TTL)}"
  EURODNS_TTL="${EURODNS_TTL:-$EURODNS_TTL_DEFAULT}"

  if [ -z "$EURODNS_APP_ID" ] || [ -z "$EURODNS_API_KEY" ]; then
    EURODNS_APP_ID=""
    EURODNS_API_KEY=""
    _err "You didn't specify EuroDNS App ID and API Key."
    _err "Please export EURODNS_APP_ID and EURODNS_API_KEY and try again."
    return 1
  fi

  _saveaccountconf_mutable EURODNS_APP_ID "$EURODNS_APP_ID"
  _saveaccountconf_mutable EURODNS_API_KEY "$EURODNS_API_KEY"
  if [ "$EURODNS_API_URL" != "$EURODNS_API_DEFAULT" ]; then
    _saveaccountconf_mutable EURODNS_API_URL "$EURODNS_API_URL"
  fi
  if [ "$EURODNS_TTL" != "$EURODNS_TTL_DEFAULT" ]; then
    _saveaccountconf_mutable EURODNS_TTL "$EURODNS_TTL"
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  _info "Adding TXT record"
  if _eurodns_add_txt_record "$_domain" "$_sub_domain" "$txtvalue"; then
    _info "Added TXT record successfully."
    return 0
  else
    _err "Failed to add TXT record."
    return 1
  fi
}

#Usage: fulldomain txtvalue
dns_eurodns_rm() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue=$2

  _info "Using EuroDNS DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  EURODNS_APP_ID="${EURODNS_APP_ID:-$(_readaccountconf_mutable EURODNS_APP_ID)}"
  EURODNS_API_KEY="${EURODNS_API_KEY:-$(_readaccountconf_mutable EURODNS_API_KEY)}"
  EURODNS_API_URL="${EURODNS_API_URL:-$(_readaccountconf_mutable EURODNS_API_URL)}"
  EURODNS_API_URL="${EURODNS_API_URL:-$EURODNS_API_DEFAULT}"

  if [ -z "$EURODNS_APP_ID" ] || [ -z "$EURODNS_API_KEY" ]; then
    EURODNS_APP_ID=""
    EURODNS_API_KEY=""
    _err "You didn't specify EuroDNS App ID and API Key."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  _info "Removing TXT record"
  if _eurodns_rm_txt_record "$_domain" "$_sub_domain" "$txtvalue"; then
    _info "Removed TXT record successfully."
    return 0
  else
    _err "Failed to remove TXT record."
    return 1
  fi
}

####################  Private functions below ##################################

# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi

    _eurodns_rest GET "dns-zones/$h"
    if [ "$?" != "0" ]; then
      if [ "$_code" = "404" ]; then
        _debug "Zone $h not found, continuing..."
      else
        _err "API error looking up zone $h"
        return 1
      fi
      p=$i
      i=$(_math "$i" + 1)
      continue
    fi

    if _contains "$response" '"name"'; then
      if [ "$i" = "1" ]; then
        _sub_domain="@"
      else
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      fi
      _domain=$h
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}

_eurodns_add_txt_record() {
  domain=$1
  subdomain=$2
  txtvalue=$3

  data='[{"type":"TXT","host":"'"$subdomain"'","rdata":"'"$txtvalue"'","ttl":'"$EURODNS_TTL"'}]'

  _debug "Adding TXT record via API"
  if _eurodns_rest POST "dns-zones/$domain/dns-records" "$data"; then
    if _contains "$response" "$txtvalue"; then
      return 0
    fi
  fi
  _err "Failed to add TXT record"
  return 1
}

_eurodns_rm_txt_record() {
  domain=$1
  subdomain=$2
  txtvalue=$3

  _debug "Getting current zone data for $domain"

  if ! _eurodns_rest GET "dns-zones/$domain"; then
    _err "Failed to get zone data"
    return 1
  fi

  zone_data=$(echo "$response" | _normalizeJson)
  _debug2 zone_data "$zone_data"

  # Find the record ID matching our TXT record
  record_id=$(echo "$zone_data" | tr '{' '\n' | grep -F '"TXT"' | grep -F "\"$subdomain\"" | grep -F "\"$txtvalue\"" | _egrep_o '"id" *: *[0-9]+' | cut -d : -f 2 | _head_n 1)
  _debug record_id "$record_id"

  if [ -z "$record_id" ]; then
    _info "TXT record not found or already removed"
    return 0
  fi

  _debug "Deleting TXT record $record_id"
  if ! _eurodns_rest DELETE "dns-zones/$domain/dns-records/$record_id"; then
    _err "Failed to delete TXT record"
    return 1
  fi

  return 0
}

# Usage: _eurodns_rest METHOD ENDPOINT [DATA]
_eurodns_rest() {
  method=$1
  endpoint=$2
  data="$3"

  export _H1="X-APP-ID: $EURODNS_APP_ID"
  export _H2="X-API-KEY: $EURODNS_API_KEY"
  export _H3="Content-Type: application/json"

  url="$EURODNS_API_URL/$endpoint"

  _debug2 url "$url"
  _debug2 method "$method"
  _debug2 data "$data"

  : >"$HTTP_HEADER"

  if [ "$method" = "GET" ]; then
    response="$(_get "$url")"
  else
    response="$(_post "$data" "$url" "" "$method")"
  fi

  _ret="$?"
  unset _H1 _H2 _H3
  _debug2 response "$response"

  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug2 _code "$_code"

  if [ "$_ret" != "0" ]; then
    _err "Error calling API: $endpoint"
    return 1
  fi

  if [ "$_code" != "200" ] && [ "$_code" != "201" ] && [ "$_code" != "204" ]; then
    if [ "$_code" != "404" ]; then
      _err "API error (HTTP $_code): $response"
    fi
    return 1
  fi

  return 0
}
