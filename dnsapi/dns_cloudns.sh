#!/usr/bin/env sh

# Author: Boyan Peychev <boyan at cloudns dot net>
# Repository: https://github.com/ClouDNS/acme.sh/

#CLOUDNS_AUTH_ID=XXXXX
#CLOUDNS_SUB_AUTH_ID=XXXXX
#CLOUDNS_AUTH_PASSWORD="YYYYYYYYY"
CLOUDNS_API="https://api.cloudns.net"

########  Public functions #####################

#Usage: dns_cloudns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_cloudns_add() {
  _info "Using cloudns"

  if ! _dns_cloudns_init_check; then
    return 1
  fi

  res="$(_dns_cloudns_get_zone_name "$1")"
  zone="$( echo $res | cut -d ' ' -f 1 )"
  master="$( echo $res | cut -d ' ' -f 2 )"


  _debug master "$master"


  if [ -z "$zone" ]; then
    _err "Missing DNS zone at ClouDNS. Please log into your control panel and create the required DNS zone for the initial setup."
    return 1
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"
  record=$2

  _debug zone "$zone"
  
  _debug host "$host"
  _debug record "$record"

  _info "Adding the TXT record for $1"
  _dns_cloudns_http_api_call "dns/add-record.json" "domain-name=$master&record-type=TXT&host=$host&record=$record&ttl=60"
  if ! _contains "$response" "\"status\":\"Success\""; then
    _err "Record cannot be added."
    return 1
  fi
  _info "Added."

  return 0
}

#Usage: dns_cloudns_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_cloudns_rm() {
  _info "Using cloudns"

  if ! _dns_cloudns_init_check; then
    return 1
  fi

  if [ -z "$zone" ]; then
    #zone="$(_dns_cloudns_get_zone_name "$1")"
    res="$(_dns_cloudns_get_zone_name "$1")"
    zone=$( echo $res | cut -d ' ' -f 1 )
    master=$( echo $res | cut -d ' ' -f 2 )

    _debug master "$master"

    if [ -z "$zone" ]; then
      _err "Missing DNS zone at ClouDNS. Please log into your control panel and create the required DNS zone for the initial setup."
      return 1
    fi
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"
  record=$2


  _dns_cloudns_http_api_call "dns/records.json" "domain-name=$master&host=$host&type=TXT"
  if ! _contains "$response" "\"id\":"; then
    return 1
  fi

  for i in $(echo "$response" | tr '{' "\n" | grep "$record"); do
    record_id=$(echo "$i" | tr ',' "\n" | grep -E '^"id"' | sed -re 's/^\"id\"\:\"([0-9]+)\"$/\1/g')

    if [ -n "$record_id" ]; then
      _debug zone "$zone"
      _debug master "$master"
      _debug host "$host"
      _debug record "$record"
      _debug record_id "$record_id"

      _info "Deleting the TXT record for $1"
      _dns_cloudns_http_api_call "dns/delete-record.json" "domain-name=$master&record-id=$record_id"

      if ! _contains "$response" "\"status\":\"Success\""; then
        _err "The TXT record for $1 cannot be deleted."
      else
        _info "Deleted."
      fi
    fi
  done

  return 0
}

####################  Private functions below ##################################
_dns_cloudns_init_check() {
  if [ -n "$CLOUDNS_INIT_CHECK_COMPLETED" ]; then
    return 0
  fi

  CLOUDNS_AUTH_ID="${CLOUDNS_AUTH_ID:-$(_readaccountconf_mutable CLOUDNS_AUTH_ID)}"
  CLOUDNS_SUB_AUTH_ID="${CLOUDNS_SUB_AUTH_ID:-$(_readaccountconf_mutable CLOUDNS_SUB_AUTH_ID)}"
  CLOUDNS_AUTH_PASSWORD="${CLOUDNS_AUTH_PASSWORD:-$(_readaccountconf_mutable CLOUDNS_AUTH_PASSWORD)}"
  if [ -z "$CLOUDNS_AUTH_ID$CLOUDNS_SUB_AUTH_ID" ] || [ -z "$CLOUDNS_AUTH_PASSWORD" ]; then
    CLOUDNS_AUTH_ID=""
    CLOUDNS_SUB_AUTH_ID=""
    CLOUDNS_AUTH_PASSWORD=""
    _err "You don't specify cloudns api id and password yet."
    _err "Please create you id and password and try again."
    return 1
  fi

  if [ -z "$CLOUDNS_AUTH_ID" ] && [ -z "$CLOUDNS_SUB_AUTH_ID" ]; then
    _err "CLOUDNS_AUTH_ID or CLOUDNS_SUB_AUTH_ID is not configured"
    return 1
  fi

  if [ -z "$CLOUDNS_AUTH_PASSWORD" ]; then
    _err "CLOUDNS_AUTH_PASSWORD is not configured"
    return 1
  fi

  _dns_cloudns_http_api_call "dns/login.json" ""

  if ! _contains "$response" "\"status\":\"Success\""; then
    _err "Invalid CLOUDNS_AUTH_ID or CLOUDNS_AUTH_PASSWORD. Please check your login credentials."
    return 1
  fi

  # save the api id and password to the account conf file.
  _saveaccountconf_mutable CLOUDNS_AUTH_ID "$CLOUDNS_AUTH_ID"
  _saveaccountconf_mutable CLOUDNS_SUB_AUTH_ID "$CLOUDNS_SUB_AUTH_ID"
  _saveaccountconf_mutable CLOUDNS_AUTH_PASSWORD "$CLOUDNS_AUTH_PASSWORD"

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

    #{"name":"effectivein.com","type":"cloud","zone":"domain","status":"1","cloud-master":"keyindices.net"}%                                                                                                                                                                       ➜  acme.sh git:(master) curl https://api.cloudns.net/dns/get-zone-info.json\?auth-id\=5164\&auth-password\=JwB3xzNRgMS6rsDEG\&domain-name\=kaicdn.com
    #{"name":"kaicdn.com","type":"master","zone":"domain","status":"1"}%


    if ! _contains "$response" "\"status\":\"Failed\""; then
      if _contains "$response" "\"type\":\"cloud\""; then
        master=$( echo "$response" | grep -o '"cloud-master":"[^"]*' | grep -o '[^"]*$' )
      else
        master="$zoneForCheck"
      fi

      echo "$zoneForCheck" "$master" 

      return 0
    fi

    i=$(_math "$i" + 1)
  done
  return 1
}

_dns_cloudns_http_api_call() {
  method=$1

  _debug CLOUDNS_AUTH_ID "$CLOUDNS_AUTH_ID"
  _debug CLOUDNS_SUB_AUTH_ID "$CLOUDNS_SUB_AUTH_ID"
  _debug CLOUDNS_AUTH_PASSWORD "$CLOUDNS_AUTH_PASSWORD"

  if [ -n "$CLOUDNS_SUB_AUTH_ID" ]; then
    auth_user="sub-auth-id=$CLOUDNS_SUB_AUTH_ID"
  else
    auth_user="auth-id=$CLOUDNS_AUTH_ID"
  fi

  if [ -z "$2" ]; then
    data="$auth_user&auth-password=$CLOUDNS_AUTH_PASSWORD"
  else
    data="$auth_user&auth-password=$CLOUDNS_AUTH_PASSWORD&$2"
  fi

  response="$(_get "$CLOUDNS_API/$method?$data")"

  _debug response "$response"

  return 0
}
