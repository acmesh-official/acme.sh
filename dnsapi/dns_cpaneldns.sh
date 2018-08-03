#!/usr/bin/env sh

# Author: K.D. Eenkhoorn <k dot eenkhoorn at gmail dot com>
# Based on work of Boyan Peychev <boyan at cloudns dot net>

# This script is a plugin for acme.sh found in te repository https://github.com/Neilpang/acme.sh.
# It's use is to add TXT verificationrecords to CPanel's DNS for Letsencrypt certificates.
# In general, before you start issueing a new certificate, you have to set a few variables for this plugin once.
# These variables can be found in the first lines of the script.

# These are:

# CPANELDNS_AUTH_ID = Your CPanel's User ID
# CPANELDNS_AUTH_PASSWORD = Your CPanel's User ID password
# CPANELDNS_API = Your Cpanel's web adress including portnumber, mostly 2083

# These one-time set variables will be saved for later use in the configuration of acme.sh.

# Usage example:

# export CPANELDNS_AUTH_ID="MY_Account"
# export CPANELDNS_AUTH_PASSWORD="My_Password"
# export CPANELDNS_API="https://www.example.com:2083/"

# ./acme.sh --issue --dns dns_cpaneldns -d example.com -d www.example.com

# Default variables, set these only in specific cases
#CPANELDNS_AUTH_ID="xxxxxxxx"
#CPANELDNS_AUTH_PASSWORD="yyyyyyyyyyy"
#CPANELDNS_API="https://zzz.zzz.zzz:2083/"

#####################  Public functions #####################

#Usage: dns_cpaneldns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_cpaneldns_add() {
  _info "Using CPanelDNS"

  if ! _dns_cpaneldns_init_check; then
    return 1
  fi

  zone="$(_dns_cpaneldns_get_zone_name "$1")"
  if [ -z "$zone" ]; then
    _err "Missing DNS zone at CPanelDNS. Please log into your control panel and create the required DNS zone for the initial setup."
    return 1
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"

  record=$2

  _debug zone "$zone"
  _debug host "$host"
  _debug record "$record"

  _info "Adding the TXT record for $1"
  _dns_cpaneldns_http_api_call "cpanel_jsonapi_module=ZoneEdit" "cpanel_jsonapi_func=add_zone_record&domain=$zone&name=$host&type=TXT&txtdata=$record&ttl=60"
  if ! _contains "$response" "\"status\":1"; then
    _err "Record cannot be added."
    return 1
  fi
  _info "Added."

  return 0
}

#Usage: dns_cpaneldns_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_cpaneldns_rm() {
  _info "Using CPanelDNS"

  if ! _dns_cpaneldns_init_check; then
    return 1
  fi

  if [ -z "$zone" ]; then
    zone="$(_dns_cpaneldns_get_zone_name "$1")"
    if [ -z "$zone" ]; then
      _err "Missing DNS zone at CPanelDNS. Please log into your control panel and create the required DNS zone for the initial setup."
      return 1
    fi
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"
  record=$2

  while _dns_cpaneldns_get_record "$zone" "$host" "$record"; do

    if [ ! -z "$record_id" ]; then
      _debug zone "$zone"
      _debug host "$host"
      _debug record "$record"
      _debug record_id "$record_id"

      _info "Deleting the TXT record for $1"
      _dns_cpaneldns_http_api_call "cpanel_jsonapi_module=ZoneEdit" "cpanel_jsonapi_func=remove_zone_record&domain=$zone&line=$record_id"

      if ! _contains "$response" "\"status\":1"; then
        _err "The TXT record for $1 cannot be deleted."
      else
        _info "Deleted."
      fi
    fi
  done

  return 0
}

####################  Private functions below ##################################
_dns_cpaneldns_init_check() {
  if [ ! -z "$CPANELDNS_INIT_CHECK_COMPLETED" ]; then
    return 0
  fi

  CPANELDNS_AUTH_ID="${CPANELDNS_AUTH_ID:-$(_readaccountconf_mutable CPANELDNS_AUTH_ID)}"
  CPANELDNS_AUTH_PASSWORD="${CPANELDNS_AUTH_PASSWORD:-$(_readaccountconf_mutable CPANELDNS_AUTH_PASSWORD)}"
  CPANELDNS_API="${CPANELDNS_API:-$(_readaccountconf_mutable CPANELDNS_API)}"

  if [ -z "$CPANELDNS_AUTH_ID" ] || [ -z "$CPANELDNS_AUTH_PASSWORD" ] || [ -z "$CPANELDNS_API" ]; then
    CPANELDNS_AUTH_ID=""
    CPANELDNS_AUTH_PASSWORD=""
    CPANELDNS_API=""
    _err "You don't specify cpaneldns api id and password or api web interface yet."
    _err "Please create you id and password and api and try again."
    return 1
  fi

  if [ -z "$CPANELDNS_AUTH_ID" ]; then
    _err "CPANELDNS_AUTH_ID is not configured"
    return 1
  fi

  if [ -z "$CPANELDNS_AUTH_PASSWORD" ]; then
    _err "CPANELDNS_AUTH_PASSWORD is not configured"
    return 1
  fi

  if [ -z "$CPANELDNS_API" ]; then
    _err "CPANELDNS_API is not configured"
    return 1
  fi

  # There is no login function for the API so checking if there is news to verify credentials
  _dns_cpaneldns_http_api_call "cpanel_jsonapi_module=News" "cpanel_jsonapi_func=does_news_exist"

  if ! _contains "$response" "\"func\":\"does_news_exist\""; then
    _err "Invalid CPANELDNS_AUTH_ID or CPANELDNS_AUTH_PASSWORD. Please check your login credentials."
    return 1
  fi

  # save the api id and password to the account conf file.
  _saveaccountconf_mutable CPANELDNS_AUTH_ID "$CPANELDNS_AUTH_ID"
  _saveaccountconf_mutable CPANELDNS_AUTH_PASSWORD "$CPANELDNS_AUTH_PASSWORD"
  _saveaccountconf_mutable CPANELDNS_API "$CPANELDNS_API"

  CPANELDNS_INIT_CHECK_COMPLETED=1

  return 0
}

_dns_cpaneldns_get_zone_name() {
  i=2
  while true; do
    zoneForCheck="$(printf "%s" "$1" | cut -d . -f $i-100)"
    if [ -z "$zoneForCheck" ]; then
      return 1
    fi

    _debug zoneForCheck "$zoneForCheck"

    _dns_cpaneldns_http_api_call "cpanel_jsonapi_module=ZoneEdit" "cpanel_jsonapi_func=fetchzone&domain=$zoneForCheck"

    if ! _contains "$response" "\"status\":0"; then
      echo "$zoneForCheck"
      return 0
    fi

    i="$(_math "$i" + 1)"
  done
  return 1
}

_dns_cpaneldns_get_record() {

  zone=$1
  host=$2
  record=$3

  _debug zone "$zone"
  _debug host "$host"
  _debug record "$record"

  _dns_cpaneldns_http_api_call "cpanel_jsonapi_module=ZoneEdit" "cpanel_jsonapi_func=fetchzone_records&domain=$zone&$name=$host&type=TXT&txtdata=$record"
  if ! _contains "$response" "\"line\":"; then
    _info "No records left matching TXT host."
    record_id=""
    return 1
  else
    recordlist="$(echo "$response" | tr '{' "\n" | grep "$record" | _head_n 1)"
    record_id="$(echo "$recordlist" | tr ',' "\n" | grep -E '^"line"' | sed -re 's/^\"line\"\:\"([0-9]+)\"$/\1/g' | cut -d ":" -f 2)"

    _info "Removing record ID: $record_id"

    _debug record_id "$record_id"

    return 0
  fi
}

_dns_cpaneldns_http_api_call() {

  method=$1

  _debug CPANELDNS_AUTH_ID "$CPANELDNS_AUTH_ID"
  _debug CPANELDNS_AUTH_PASSWORD "$CPANELDNS_AUTH_PASSWORD"

  if [ -z "$2" ]; then
    data="&$method"
  else
    data="&$method&$2"
  fi

  basicauth="$(printf %s "$CPANELDNS_AUTH_ID:$CPANELDNS_AUTH_PASSWORD" | _base64)"
  export _H1="Authorization: Basic $basicauth)"

  response="$(_get "$CPANELDNS_API/json-api/cpanel?cpanel_jsonapi_user=user&cpanel_jsonapi_apiversion=2$data")"
  _debug response "$response"
  return 0
}
