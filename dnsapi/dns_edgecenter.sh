#!/bin/bash
# shellcheck disable=SC2034
dns_edgecenter_info='EdgeCenter DNS
Site: https://edgecenter.ru
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_edgecenter
Options:
 EDGECENTER_API_KEY auth APIKey
Author: Konstantin Ruchev <konstantin.ruchev@edgecenter.ru>
'

EDGECENTER_API="https://api.edgecenter.ru"
DOMAIN_TYPE=
DOMAIN_MASTER=

########  Public functions #####################

#Usage: dns_edgecenter_add   _acme-challenge.www.domain.com   "TXT_RECORD_VALUE"
dns_edgecenter_add() {
  _info "Using EdgeCenter"
  
  if ! _dns_edgecenter_init_check; then
    return 1
  fi

  zone="$(_dns_edgecenter_get_zone_name "$1")"
  if [ -z "$zone" ]; then
    _err "Missing DNS zone at EdgeCenter. Please log into your control panel and create the required DNS zone for the initial setup."
    return 1
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"
  record=$2

  _debug "Zone" "$zone"
  _debug "Host" "$host"
  _debug "Record" "$record"

  _info "Adding the TXT record for $1"
  _dns_edgecenter_http_api_call "post" "dns/v2/zones/$zone/$host.$zone/txt" "{\"resource_records\": [ { \"content\": [\"$record\"] } ], \"ttl\": 60 }"

  if _contains "$response" "\"error\":\"rrset is already exists\""; then
    _debug "Record already exists, updating it."
    _dns_edgecenter_http_api_call "put" "dns/v2/zones/$zone/$host.$zone/txt" "{\"resource_records\": [ { \"content\": [\"$record\"] } ], \"ttl\": 60 }"
    return 1
  fi  
  if _contains "$response" "\"exception\":"; then
    _err "Record cannot be added."
    return 1
  fi
  _info "TXT record added successfully."
  return 0
}

#Usage: dns_edgecenter_rm   _acme-challenge.www.domain.com   "TXT_RECORD_VALUE"
dns_edgecenter_rm() {
  _info "Using EdgeCenter"
  
  if ! _dns_edgecenter_init_check; then
    return 1
  fi

  if [ -z "$zone" ]; then
    zone="$(_dns_edgecenter_get_zone_name "$1")"
    if [ -z "$zone" ]; then
      _err "Missing DNS zone at EdgeCenter. Please log into your control panel and create the required DNS zone for the initial setup."
      return 1
    fi
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"
  record=$2
  
  _debug "Zone" "$zone"
  _debug "Host" "$host"
  
  _info "Deleting the TXT record for $1"
  _dns_edgecenter_http_api_call "delete" "dns/v2/zones/$zone/$host.$zone/txt"
  
  if [ -z "$response" ]; then
    _info "TXT record deleted successfully."
  else
    _err "The TXT record for $host cannot be deleted."
  fi

  return 0
}

####################  Private functions below ##################################

_dns_edgecenter_init_check() {
  if [ -n "$EDGECENTER_INIT_CHECK_COMPLETED" ]; then
    _debug "EdgeCenter initialization already completed."
    return 0
  fi

  EDGECENTER_API_KEY="${EDGECENTER_API_KEY:-$(_readaccountconf_mutable EDGECENTER_API_KEY)}"
  if [ -z "$EDGECENTER_API_KEY" ]; then
    _err "You haven't specified the EdgeCenter API key yet."
    _err "Please set EDGECENTER_API_KEY and try again."
    return 1
  fi

  _debug "EdgeCenter API Key" "$EDGECENTER_API_KEY"

  _dns_edgecenter_http_api_call "get" "dns/v2/clients/me/features"
  if ! _contains "$response" "\"id\":"; then
    _err "Invalid EDGECENTER_API_KEY. Please check your credentials."
    return 1
  fi

  _saveaccountconf_mutable EDGECENTER_API_KEY "$EDGECENTER_API_KEY"

  EDGECENTER_INIT_CHECK_COMPLETED=1
  _debug "EdgeCenter initialization completed."
  return 0
}

_dns_edgecenter_get_zone_name() {
  i=2
  while true; do
    zoneForCheck=$(printf "%s" "$1" | cut -d . -f $i-100)

    if [ -z "$zoneForCheck" ]; then
      _debug "No zone found in domain: $1"
      return 1
    fi

    _debug "Trying zone" "$zoneForCheck"
    _dns_edgecenter_http_api_call "get" "dns/v2/zones/$zoneForCheck"

    if ! _contains "$response" "\"error\":\"get zone by name: zone is not found\""; then
      _debug "Zone found" "$zoneForCheck"
      echo "$zoneForCheck"
      return 0
    fi

    i=$(_math "$i" + 1)
  done
  return 1
}

_dns_edgecenter_http_api_call() {
  method=$1
  api_method=$2
  body=$3

  _debug "EdgeCenter API Key in call" "$EDGECENTER_API_KEY"
  
  export _H1="Authorization: APIKey $EDGECENTER_API_KEY"

  case "$method" in
    *get*)
      _debug "HTTP GET: $EDGECENTER_API/$api_method"
      response="$(_get "$EDGECENTER_API/$api_method")"
      ;;
    *post*)
      _debug "HTTP POST: $EDGECENTER_API/$api_method"
      _debug "Payload:" "$body"
      response="$(_post "$body" "$EDGECENTER_API/$api_method")"
      ;;
    *delete*)
      _debug "HTTP DELETE: $EDGECENTER_API/$api_method"
      response="$(_post "" "$EDGECENTER_API/$api_method" "" "DELETE")"
      ;;
    *put*)
      _debug "HTTP PUT: $EDGECENTER_API/$api_method"
      response="$(_post "" "$EDGECENTER_API/$api_method" "" "PUT")"
      ;;
    *)
      _err "HTTP method $method not supported."
      return 1
      ;;
  esac

  _debug "HTTP response" "$response"

  return 0
}
