#!/usr/bin/env sh

# Author: Boyan Peychev <boyan at cloudns dot net>
# Modified for Leaseweb: M-Boone

LEASEWEB_API="https://api.leaseweb.com/hosting/v2/domains"

########  Public functions #####################

#Usage: dns_leaseweb_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_leaseweb_add() {
  
  if ! _dns_leaseweb_init_check; then
    return 1
  fi
  
  zone="$(_dns_leaseweb_get_zone_name "$1")"
  if [ -z "$zone" ]; then
    _err "Missing DNS zone at Leaseweb. Please log into your control panel and create the required DNS zone for the initial setup."
    return 1
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"
  record=$2

  _debug zone "$zone"
  _debug host "$host"
  _debug record "$record"

  _info "Adding the TXT record for $1"
  _dns_leaseweb_http_api_call "POST" "/$zone/resourceRecordSets" "{\"name\": \"$1\",  \"type\": \"TXT\",  \"content\": [    \"$record\"  ],  \"ttl\": 60}" 
  if [ -z "$response" ] || _contains "$response" "\"errorMessage\""; then
    _err "Record cannot be added. $response"
    return 1
  fi
  _info "Added."

  return 0
}

#Usage: dns_leaseweb_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_leaseweb_rm() {
  if ! _dns_leaseweb_init_check; then
    return 1
  fi

  if [ -z "$zone" ]; then
    zone="$(_dns_leaseweb_get_zone_name "$1")"
    if [ -z "$zone" ]; then
      _err "Missing DNS zone at leaseweb. Please log into your control panel and create the required DNS zone for the initial setup."
      return 1
    fi
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"
  record=$2
  
  _debug zone "$zone"
  _debug host "$host"
  _debug record "$record"

  _dns_leaseweb_http_api_call "GET" "/$zone/resourceRecordSets/$1/TXT"
   if [ -z "$response" ] || _contains "$response" "\"errorMessage\""; then
   _err "Could not find resource records sets."
    return 1
  fi

  _info "Deleting the TXT record for $1"
  _dns_leaseweb_http_api_call "DELETE" "/$zone/resourceRecordSets/$1/TXT"

   #no response from deleting, maybe because we mis-used _post() function, check again
   _dns_leaseweb_http_api_call "GET" "/$zone/resourceRecordSets/$1/TXT"
   if [ -n "$response" ] && ! _contains "$response" "\"errorMessage\""; then
   _err "The TXT record for $1 cannot be deleted."
    return 1
  fi

  return 0
}

####################  Private functions below ##################################
_dns_leaseweb_init_check() {
  _info "Using leaseweb"

  if [ ! -z "$leaseweb_INIT_CHECK_COMPLETED" ]; then
    return 0
  fi

  leaseweb_API_KEY="${leaseweb_API_KEY:-$(_readaccountconf_mutable leaseweb_API_KEY)}"
  if [ -z "$leaseweb_API_KEY" ]; then
    leaseweb_API_KEY=""
    _err "You didn't specify a leaseweb api key yet."
    _err "Please create the key and try again."
    return 1
  fi

  _dns_leaseweb_http_api_call "GET" ""

  if [ -z "$response" ] || _contains "$response" "\"errorMessage\""; then
    _err "Invalid leaseweb_API_KEY. Please check your API KEY credentials. Error: $response"
    return 1
  fi

  # save the api id and password to the account conf file.
  _saveaccountconf_mutable leaseweb_API_KEY "$leaseweb_API_KEY"

  leaseweb_INIT_CHECK_COMPLETED=1

  return 0
}

_dns_leaseweb_get_zone_name() {
  i=2
  while true; do
    zoneForCheck=$(printf "%s" "$1" | cut -d . -f $i-100)

    if [ -z "$zoneForCheck" ]; then
      return 1
    fi

    _debug zoneForCheck "$zoneForCheck"

    _dns_leaseweb_http_api_call "GET" "/$zoneForCheck"

    if [ -n "$response" ] && ! _contains "$response" "\"errorMessage\""; then
      echo "$zoneForCheck"
      return 0
    fi

    i=$(_math "$i" + 1)
  done
  return 1
}

#usage: method    path (with leading slash)   data
_dns_leaseweb_http_api_call() {
  method=$1
  path=$2

  _debug leasewebParams "$1 $2 $3"
  _debug leaseweb_API_KEY "$leaseweb_API_KEY"  
  export _H1="X-Lsw-Auth: $leaseweb_API_KEY"


  if [ "$method" != "GET" ]; then
	data=""
	base64enc=""
	mimetype=""
	
	if [ -n "$3" ]; then
		data=$3
		base64enc="1"
		mimetype="application/json"
	fi
	response="$(_post "$data" "$LEASEWEB_API$path" "$base64enc" "$method" "$mimetype")"	
  else
    response="$(_get "$LEASEWEB_API$path")"
  fi

  _debug response "$response"

  return 0
}
