#!/usr/bin/env sh

# Acme.sh DNS API wrapper for websupport.sk
#
# Original author: trgo.sk (https://github.com/trgosk)
# Tweaks by: akulumbeg (https://github.com/akulumbeg)
# Report Bugs here: https://github.com/akulumbeg/acme.sh

# Requirements: API Key and Secret from https://admin.websupport.sk/en/auth/apiKey
#
# WS_ApiKey="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# (called "Identifier" in the WS Admin)
#
# WS_ApiSecret="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
# (called "Secret key" in the WS Admin)

WS_Api="https://rest.websupport.sk"

########  Public functions #####################

dns_websupport_add() {
  fulldomain=$1
  txtvalue=$2

  WS_ApiKey="${WS_ApiKey:-$(_readaccountconf_mutable WS_ApiKey)}"
  WS_ApiSecret="${WS_ApiSecret:-$(_readaccountconf_mutable WS_ApiSecret)}"

  if [ "$WS_ApiKey" ] && [ "$WS_ApiSecret" ]; then
    _saveaccountconf_mutable WS_ApiKey "$WS_ApiKey"
    _saveaccountconf_mutable WS_ApiSecret "$WS_ApiSecret"
  else
    WS_ApiKey=""
    WS_ApiSecret=""
    _err "You did not specify the API Key and/or API Secret"
    _err "You can get the API login credentials from https://admin.websupport.sk/en/auth/apiKey"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # For wildcard cert, the main root domain and the wildcard domain have the same txt subdomain name, so
  # we can not use updating anymore.
  #  count=$(printf "%s\n" "$response" | _egrep_o "\"count\":[^,]*" | cut -d : -f 2)
  #  _debug count "$count"
  #  if [ "$count" = "0" ]; then
  _info "Adding record"
  if _ws_rest POST "/v1/user/self/zone/$_domain/record" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"ttl\":120}"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
      return 0
    elif _contains "$response" "The record already exists"; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1

}

dns_websupport_rm() {
  fulldomain=$1
  txtvalue=$2

  _debug2 fulldomain "$fulldomain"
  _debug2 txtvalue "$txtvalue"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _ws_rest GET "/v1/user/self/zone/$_domain/record"

  if [ "$(printf "%s" "$response" | tr -d " " | grep -c \"items\")" -lt "1" ]; then
    _err "Error: $response"
    return 1
  fi

  record_line="$(_get_from_array "$response" "$txtvalue")"
  _debug record_line "$record_line"
  if [ -z "$record_line" ]; then
    _info "Don't need to remove."
  else
    record_id=$(echo "$record_line" | _egrep_o "\"id\": *[^,]*" | _head_n 1 | cut -d : -f 2 | tr -d \" | tr -d " ")
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if ! _ws_rest DELETE "/v1/user/self/zone/$_domain/record/$record_id"; then
      _err "Delete record error."
      return 1
    fi
    if [ "$(printf "%s" "$response" | tr -d " " | grep -c \"success\")" -lt "1" ]; then
      return 1
    else
      return 0
    fi
  fi

}

####################  Private Functions ##################################

_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _ws_rest GET "/v1/user/self/zone"; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _domain_id=$(echo "$response" | _egrep_o "\[.\"id\": *[^,]*" | _head_n 1 | cut -d : -f 2 | tr -d \" | tr -d " ")
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_ws_rest() {
  me=$1
  pa="$2"
  da="$3"

  _debug2 api_key "$WS_ApiKey"
  _debug2 api_secret "$WS_ApiSecret"

  timestamp=$(_time)
  datez="$(_utc_date | sed "s/ /T/" | sed "s/$/+0000/")"
  canonical_request="${me} ${pa} ${timestamp}"
  signature_hash=$(printf "%s" "$canonical_request" | _hmac sha1 "$(printf "%s" "$WS_ApiSecret" | _hex_dump | tr -d " ")" hex)
  basicauth="$(printf "%s:%s" "$WS_ApiKey" "$signature_hash" | _base64)"

  _debug2 method "$me"
  _debug2 path "$pa"
  _debug2 data "$da"
  _debug2 timestamp "$timestamp"
  _debug2 datez "$datez"
  _debug2 canonical_request "$canonical_request"
  _debug2 signature_hash "$signature_hash"
  _debug2 basicauth "$basicauth"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  export _H3="Authorization: Basic ${basicauth}"
  export _H4="Date: ${datez}"

  _debug2 H1 "$_H1"
  _debug2 H2 "$_H2"
  _debug2 H3 "$_H3"
  _debug2 H4 "$_H4"

  if [ "$me" != "GET" ]; then
    _debug2 "${me} $WS_Api${pa}"
    _debug data "$da"
    response="$(_post "$da" "${WS_Api}${pa}" "" "$me")"
  else
    _debug2 "GET $WS_Api${pa}"
    response="$(_get "$WS_Api${pa}")"
  fi

  _debug2 response "$response"
  return "$?"
}

_get_from_array() {
  va="$1"
  fi="$2"
  for i in $(echo "$va" | sed "s/{/ /g"); do
    if _contains "$i" "$fi"; then
      echo "$i"
      break
    fi
  done
}
