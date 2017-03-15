#!/usr/bin/env sh

#CLOUDNS_AUTH_ID=XXXXX
#CLOUDNS_AUTH_PASSWORD="YYYYYYYYY"
CLOUDNS_API="https://api.cloudns.net"

########  Public functions #####################

#Usage: dns_cloudns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_cloudns_add() {
  _info "Using cloudns"

  if ! _dns_cloudns_init_check; then
    return 1
  fi

  zone="$(_dns_cloudns_get_zone_name "$1")"
  if [ -z "$zone" ]; then
    _err "Missing DNS zone at ClouDNS. Please log into your control panel and create the required DNS zone for the initial setup."
    return 1
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"
  record=$2
  record_id=$(_dns_cloudns_get_record_id "$zone" "$host")

  _debug zone "$zone"
  _debug host "$host"
  _debug record "$record"
  _debug record_id "$record_id"

  if [ -z "$record_id" ]; then
    _info "Adding the TXT record for $1"
    _dns_cloudns_http_api_call "dns/add-record.json" "domain-name=$zone&record-type=TXT&host=$host&record=$record&ttl=60"
    if ! _contains "$response" "\"status\":\"Success\""; then
      _err "Record cannot be added."
      return 1
    fi
    _info "Added."
  else
    _info "Updating the TXT record for $1"
    _dns_cloudns_http_api_call "dns/mod-record.json" "domain-name=$zone&record-id=$record_id&record-type=TXT&host=$host&record=$record&ttl=60"
    if ! _contains "$response" "\"status\":\"Success\""; then
      _err "The TXT record for $1 cannot be updated."
      return 1
    fi
    _info "Updated."
  fi

  return 0
}

#Usage: dns_cloudns_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_cloudns_rm() {
  _info "Using cloudns"

  if ! _dns_cloudns_init_check; then
    return 1
  fi

  if [ -z "$zone" ]; then
    zone="$(_dns_cloudns_get_zone_name "$1")"
    if [ -z "$zone" ]; then
      _err "Missing DNS zone at ClouDNS. Please log into your control panel and create the required DNS zone for the initial setup."
      return 1
    fi
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"
  record=$2
  record_id=$(_dns_cloudns_get_record_id "$zone" "$host")

  _debug zone "$zone"
  _debug host "$host"
  _debug record "$record"
  _debug record_id "$record_id"

  if [ ! -z "$record_id" ]; then
    _info "Deleting the TXT record for $1"
    _dns_cloudns_http_api_call "dns/delete-record.json" "domain-name=$zone&record-id="
    if ! _contains "$response" "\"status\":\"Success\""; then
      _err "The TXT record for $1 cannot be deleted."
      return 1
    fi
    _info "Deleted."
  fi
  return 0
}

####################  Private functions below ##################################
_dns_cloudns_init_check() {
  if [ ! -z "$CLOUDNS_INIT_CHECK_COMPLETED" ]; then
    return 0
  fi

  if [ -z "$CLOUDNS_AUTH_ID" ]; then
    _err "CLOUDNS_AUTH_ID is not configured"
    return 1
  fi

  if [ -z "$CLOUDNS_AUTH_PASSWORD" ]; then
    _err "CLOUDNS_AUTH_PASSWORD is not configured"
    return 1
  fi

  CLOUDNS_INIT_CHECK_COMPLETED=1

  return 0
}

_dns_cloudns_get_zone_name() {
  i=2
  while true; do
    zoneForCheck=$(printf "%s" "$1" | cut -d . -f $i-100)

    if [ -z "$zoneForCheck" ]; then
      return 1
    fi

    _debug zoneForCheck "$zoneForCheck"

    _dns_cloudns_http_api_call "dns/get-zone-info.json" "domain-name=$zoneForCheck"

    if ! _contains "$response" "\"status\":\"Failed\""; then
      echo "$zoneForCheck"
      return 0
    fi

    i=$(_math "$i" + 1)
  done
  return 1
}

_dns_cloudns_get_record_id() {
  _dns_cloudns_http_api_call "dns/records.json" "domain-name=$1&host=$2&type=TXT"
  if _contains "$response" "\"id\":"; then
    echo "$response" | awk 'BEGIN { FS="\"" } {print $2}'
    return 0
  fi
  return 1
}

_dns_cloudns_http_api_call() {
  method=$1

  _debug CLOUDNS_AUTH_ID "$CLOUDNS_AUTH_ID"
  _debug CLOUDNS_AUTH_PASSWORD "$CLOUDNS_AUTH_PASSWORD"

  data="auth-id=$CLOUDNS_AUTH_ID&auth-password=$CLOUDNS_AUTH_PASSWORD&$2"

  response="$(_get "$CLOUDNS_API/$method?$data")"

  _debug2 response "$response"

  return 0
}
