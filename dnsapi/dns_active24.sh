#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_active24_info='Active24.cz
Site: Active24.cz
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_active24
Options:
 Active24_ApiKey API Key. Called "Identifier" in the Active24 Admin
 Active24_ApiSecret API Secret. Called "Secret key" in the Active24 Admin
Issues: github.com/acmesh-official/acme.sh/issues/2059
'

Active24_Api="https://rest.active24.cz"
# export Active24_ApiKey=ak48l3h7-ak5d-qn4t-p8gc-b6fs8c3l
# export Active24_ApiSecret=ajvkeo3y82ndsu2smvxy3o36496dcascksldncsq

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_active24_add() {
  fulldomain=$1
  txtvalue=$2

  _active24_init

  _info "Adding txt record"
  if _active24_rest POST "/v2/service/$_service_id/dns/record" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"ttl\":300}"; then
    if _contains "$response" "error"; then
      _err "Add txt record error."
      return 1
    else
      _info "Added, OK"
      return 0
    fi
  fi

  _err "Add txt record error."
  return 1
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_active24_rm() {
  fulldomain=$1
  txtvalue=$2

  _active24_init

  _debug "Getting txt records"
  # The API needs to send data in body in order the filter to work
  # TODO: web can also add content $txtvalue to filter and then get the id from response
  _active24_rest GET "/v2/service/$_service_id/dns/record" "{\"page\":1,\"descending\":true,\"sortBy\":\"name\",\"rowsPerPage\":100,\"totalRecords\":0,\"filters\":{\"type\":[\"TXT\"],\"name\":\"${_sub_domain}\"}}"
  #_active24_rest GET "/v2/service/$_service_id/dns/record?rowsPerPage=100"

  if _contains "$response" "error"; then
    _err "Error"
    return 1
  fi

  # Note: it might never be more than one record actually, NEEDS more INVESTIGATION
  record_ids=$(printf "%s" "$response" | _egrep_o "[^{]+${txtvalue}[^}]+" | _egrep_o '"id" *: *[^,]+' | cut -d ':' -f 2)
  _debug2 record_ids "$record_ids"

  for redord_id in $record_ids; do
    _debug "Removing record_id" "$redord_id"
    _debug "txtvalue" "$txtvalue"
    if _active24_rest DELETE "/v2/service/$_service_id/dns/record/$redord_id" ""; then
      if _contains "$response" "error"; then
        _err "Unable to remove txt record."
        return 1
      else
        _info "Removed txt record."
        return 0
      fi
    fi
  done

  _err "No txt records found."
  return 1
}

_get_root() {
  domain=$1
  i=1
  p=1

  if ! _active24_rest GET "/v1/user/self/service"; then
    return 1
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug "h" "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"$h\"" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_active24_init() {
  Active24_ApiKey="${Active24_ApiKey:-$(_readaccountconf_mutable Active24_ApiKey)}"
  Active24_ApiSecret="${Active24_ApiSecret:-$(_readaccountconf_mutable Active24_ApiSecret)}"
  #Active24_ServiceId="${Active24_ServiceId:-$(_readaccountconf_mutable Active24_ServiceId)}"

  if [ -z "$Active24_ApiKey" ] || [ -z "$Active24_ApiSecret" ]; then
    Active24_ApiKey=""
    Active24_ApiSecret=""
    _err "You don't specify Active24 api key and ApiSecret yet."
    _err "Please create your key and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable Active24_ApiKey "$Active24_ApiKey"
  _saveaccountconf_mutable Active24_ApiSecret "$Active24_ApiSecret"

  _debug "A24 API CHECK"
  if ! _active24_rest GET "/v2/check"; then
    _err "A24 API check failed with: $response"
    return 1
  fi

  if ! echo "$response" | tr -d " " | grep \"verified\":true >/dev/null; then
    _err "A24 API check failed with: $response"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _active24_get_service_id "$_domain"
  _debug _service_id "$_service_id"
}

_active24_get_service_id() {
  _d=$1
  if ! _active24_rest GET "/v1/user/self/zone/${_d}"; then
    return 1
  else
    response=$(echo "$response" | _json_decode)
    _service_id=$(echo "$response" | _egrep_o '"id" *: *[^,]+' | cut -d ':' -f 2)
  fi
}

_active24_rest() {
  m=$1
  ep_qs=$2 # with query string
  # ep=$2
  ep=$(printf "%s" "$ep_qs" | cut -d '?' -f1) # no query string
  data="$3"

  _debug "A24 $ep"
  _debug "A24 $Active24_ApiKey"
  _debug "A24 $Active24_ApiSecret"

  timestamp=$(_time)
  datez=$(date -u +"%Y%m%dT%H%M%SZ")
  canonicalRequest="${m} ${ep} ${timestamp}"
  signature=$(printf "%s" "$canonicalRequest" | _hmac sha1 "$(printf "%s" "$Active24_ApiSecret" | _hex_dump | tr -d " ")" hex)
  authorization64="$(printf "%s:%s" "$Active24_ApiKey" "$signature" | _base64)"

  export _H1="Date: ${datez}"
  export _H2="Accept: application/json"
  export _H3="Content-Type: application/json"
  export _H4="Authorization: Basic ${authorization64}"

  _debug2 H1 "$_H1"
  _debug2 H2 "$_H2"
  _debug2 H3 "$_H3"
  _debug2 H4 "$_H4"

  # _sleep 1

  if [ "$m" != "GET" ]; then
    _debug2 "${m} $Active24_Api${ep_qs}"
    _debug "data" "$data"
    response="$(_post "$data" "$Active24_Api${ep_qs}" "" "$m" "application/json")"
  else
    if [ -z "$data" ]; then
      _debug2 "GET $Active24_Api${ep_qs}"
      response="$(_get "$Active24_Api${ep_qs}")"
    else
      _debug2 "GET $Active24_Api${ep_qs} with data: ${data}"
      response="$(_post "$data" "$Active24_Api${ep_qs}" "" "$m" "application/json")"
    fi
  fi
  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
