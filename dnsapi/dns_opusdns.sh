#!/usr/bin/env sh

# shellcheck disable=SC2034
dns_opusdns_info='OpusDNS.com
Site: OpusDNS.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_opusdns
Options:
 OPUSDNS_API_Key API Key. Can be created at https://dashboard.opusdns.com/settings/api-keys
 OPUSDNS_API_Endpoint API Endpoint URL. Default "https://api.opusdns.com". Optional.
 OPUSDNS_TTL TTL for DNS challenge records in seconds. Default "60". Optional.
Issues: github.com/acmesh-official/acme.sh/issues/XXXX
Author: OpusDNS Team <https://github.com/opusdns>
'

OPUSDNS_API_Endpoint_Default="https://api.opusdns.com"
OPUSDNS_TTL_Default=60

######## Public functions ###########

# Add DNS TXT record
dns_opusdns_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using OpusDNS DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _opusdns_init; then
    return 1
  fi

  if ! _get_zone "$fulldomain"; then
    return 1
  fi

  _info "Zone: $_zone, Record: $_record_name"

  if ! _opusdns_api PATCH "/v1/dns/$_zone/records" "{\"ops\":[{\"op\":\"upsert\",\"record\":{\"name\":\"$_record_name\",\"type\":\"TXT\",\"ttl\":$OPUSDNS_TTL,\"rdata\":\"\\\"$txtvalue\\\"\"}}]}"; then
    _err "Failed to add TXT record"
    return 1
  fi

  _info "TXT record added successfully"
  return 0
}

# Remove DNS TXT record
dns_opusdns_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Removing OpusDNS DNS record"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _opusdns_init; then
    return 1
  fi

  if ! _get_zone "$fulldomain"; then
    _err "Zone not found, cleanup skipped"
    return 0
  fi

  _info "Zone: $_zone, Record: $_record_name"

  if ! _opusdns_api PATCH "/v1/dns/$_zone/records" "{\"ops\":[{\"op\":\"remove\",\"record\":{\"name\":\"$_record_name\",\"type\":\"TXT\",\"ttl\":$OPUSDNS_TTL,\"rdata\":\"\\\"$txtvalue\\\"\"}}]}"; then
    _err "Warning: Failed to remove TXT record"
    return 0
  fi

  _info "TXT record removed successfully"
  return 0
}

######## Private functions ###########

# Initialize and validate configuration
_opusdns_init() {
  OPUSDNS_API_Key="${OPUSDNS_API_Key:-$(_readaccountconf_mutable OPUSDNS_API_Key)}"
  OPUSDNS_API_Endpoint="${OPUSDNS_API_Endpoint:-$(_readaccountconf_mutable OPUSDNS_API_Endpoint)}"
  OPUSDNS_TTL="${OPUSDNS_TTL:-$(_readaccountconf_mutable OPUSDNS_TTL)}"

  if [ -z "$OPUSDNS_API_Key" ]; then
    _err "OPUSDNS_API_Key not set"
    return 1
  fi

  [ -z "$OPUSDNS_API_Endpoint" ] && OPUSDNS_API_Endpoint="$OPUSDNS_API_Endpoint_Default"
  [ -z "$OPUSDNS_TTL" ] && OPUSDNS_TTL="$OPUSDNS_TTL_Default"

  _saveaccountconf_mutable OPUSDNS_API_Key "$OPUSDNS_API_Key"
  _saveaccountconf_mutable OPUSDNS_API_Endpoint "$OPUSDNS_API_Endpoint"
  _saveaccountconf_mutable OPUSDNS_TTL "$OPUSDNS_TTL"

  _debug "Endpoint: $OPUSDNS_API_Endpoint"
  return 0
}

# Make API request
# Usage: _opusdns_api METHOD PATH [DATA]
_opusdns_api() {
  method=$1
  path=$2
  data=$3

  export _H1="X-Api-Key: $OPUSDNS_API_Key"
  export _H2="Content-Type: application/json"

  url="$OPUSDNS_API_Endpoint$path"
  _debug2 "API: $method $url"
  [ -n "$data" ] && _debug2 "Data: $data"

  if [ -n "$data" ]; then
    response=$(_post "$data" "$url" "" "$method")
  else
    response=$(_get "$url")
  fi

  if [ $? -ne 0 ]; then
    _err "API request failed"
    _debug "Response: $response"
    return 1
  fi

  _debug2 "Response: $response"
  return 0
}

# Detect zone from FQDN
# Sets: _zone, _record_name
_get_zone() {
  domain=$(echo "$1" | sed 's/\.$//')
  _debug "Finding zone for: $domain"

  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)

    if [ -z "$h" ]; then
      _err "No valid zone found for: $domain"
      return 1
    fi

    _debug "Trying: $h"
    if _opusdns_api GET "/v1/dns/$h" && _contains "$response" '"dnssec_status"'; then
      _zone="$h"
      _record_name=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      [ -z "$_record_name" ] && _record_name="@"
      return 0
    fi

    p="$i"
    i=$(_math "$i" + 1)
  done
}
