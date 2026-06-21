#!/usr/bin/env sh

# shellcheck disable=SC2034

# Credits to the authors of dnsapi/dns_pdns.sh as this reuses much of that code.

dns_poweradmin_info='Poweradmin API
Site: https://www.poweradmin.org/
Docs: https://github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_poweradmin
Options:
POWERADMIN_URL API URL (with scheme). E.g. "https://poweradmin.example.com" or "http://192.168.0.10:8080"
POWERADMIN_API_KEY API Token "pwa_xxxx"
POWERADMIN_API_VERSION Optionally override Poweradmin API version.
Issues: https://github.com/acmesh-official/acme.sh/issues/6912
Author: Jakob Næss <https://github.com/InvisibleDuck>
'

######## Public functions ####################

# Usage: dns_poweradmin_add _acme-challenge.www.domain.com "123456789ABCDEF"
# fulldomain
# txtvalue
dns_poweradmin_add() {
  fulldomain=$1
  txtvalue=$2

  POWERADMIN_URL="${POWERADMIN_URL:-$(_readaccountconf_mutable POWERADMIN_URL)}"
  POWERADMIN_API_KEY="${POWERADMIN_API_KEY:-$(_readaccountconf_mutable POWERADMIN_API_KEY)}"
  POWERADMIN_API_VERSION="${POWERADMIN_API_VERSION:-$(_readaccountconf_mutable POWERADMIN_API_VERSION)}"
  POWERADMIN_API_VERSION="${POWERADMIN_API_VERSION:-2}"

  if [ -z "$POWERADMIN_URL" ]; then
    POWERADMIN_URL=""
    _err "You didn't specify Poweradmin URL."
    _err "Please set POWERADMIN_URL and try again."
    return 1
  fi

  if [ -z "$POWERADMIN_API_KEY" ]; then
    POWERADMIN_API_KEY=""
    _err "You didn't specify Poweradmin token."
    _err "Please set POWERADMIN_API_KEY and try again."
    return 1
  fi

  # Save the api addr, key, and version to the account conf file.
  _saveaccountconf_mutable POWERADMIN_URL "$POWERADMIN_URL"
  _saveaccountconf_mutable POWERADMIN_API_KEY "$POWERADMIN_API_KEY"
  _saveaccountconf_mutable POWERADMIN_API_VERSION "$POWERADMIN_API_VERSION"

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain "$_domain"
  _debug _zone_id "$_zone_id"

  if ! _set_record "$fulldomain" "$txtvalue"; then
    return 1
  fi

  return 0
}

# Usage: dns_poweradmin_rm _acme-challenge.www.domain.com "123456789ABCDEF"
# fulldomain
# txtvalue
dns_poweradmin_rm() {
  fulldomain=$1
  txtvalue=$2

  POWERADMIN_URL="${POWERADMIN_URL:-$(_readaccountconf_mutable POWERADMIN_URL)}"
  POWERADMIN_API_KEY="${POWERADMIN_API_KEY:-$(_readaccountconf_mutable POWERADMIN_API_KEY)}"
  POWERADMIN_API_VERSION="${POWERADMIN_API_VERSION:-$(_readaccountconf_mutable POWERADMIN_API_VERSION)}"
  POWERADMIN_API_VERSION="${POWERADMIN_API_VERSION:-2}"

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain "$_domain"
  _debug _zone_id "$_zone_id"

  if ! _rm_record "$fulldomain" "$txtvalue"; then
    return 1
  fi

  return 0
}

######## Private functions below #####################

_set_record() {
  _info "Adding TXT record"
  full=$1
  new_challenge=$2

  data='{"name":"'$full'","type":"TXT","content":"'$new_challenge'","ttl":60}'

  if ! _poweradmin_rest "POST" "/api/v${POWERADMIN_API_VERSION}/zones/$_zone_id/records" "$data" "application/json"; then
    _err "Failed to add TXT record"
    return 1
  fi

  return 0
}

_rm_record() {
  _info "Remove TXT record"
  full=$1
  txtvalue=$2

  if ! _poweradmin_rest "GET" "/api/v${POWERADMIN_API_VERSION}/zones/$_zone_id/records"; then
    _err "Failed to retrieve records"
    return 1
  fi

  # The API returns: {"success":true,"data":[{"id":..., "name":"...", "type":"TXT", "content":"...", ...}]}
  _txt_record_obj=$(
    printf '%s\n' "$response" |
      sed 's/^.*"data":\[//; s/\],"message":.*$//' |
      awk '{ gsub(/},{/, "}\n{"); print }' |
      grep -F "\"name\":\"$full\"" |
      grep -F "\"type\":\"TXT\"" |
      grep -F "\"content\":\"$txtvalue\"" |
      _head_n 1
  )

  if [ -z "$_txt_record_obj" ]; then
    _info "TXT record not found for $full with content $txtvalue"
    return 0
  fi

  record_id=$(printf '%s\n' "$_txt_record_obj" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | _head_n 1)
  record_type=$(printf '%s\n' "$_txt_record_obj" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p' | _head_n 1)
  record_name=$(printf '%s\n' "$_txt_record_obj" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | _head_n 1)
  record_content=$(printf '%s\n' "$_txt_record_obj" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p' | _head_n 1)

  _debug2 "_txt_record_obj=$_txt_record_obj"
  _debug2 "record id: $record_id"
  _debug2 "record type: $record_type"
  _debug2 "record name: $record_name"
  _debug2 "record content: $record_content"

  if [ "$record_type" != "TXT" ]; then
    _err "Refusing to delete non-TXT record id=$record_id type=$record_type name=$full"
    return 1
  fi

  if ! _poweradmin_rest "DELETE" "/api/v${POWERADMIN_API_VERSION}/zones/$_zone_id/records/$record_id"; then
    _err "Failed to delete TXT record"
    return 1
  fi

  _info "Record deleted successfully"
  return 0
}

# _acme-challenge.www.domain.com
# returns
#   _domain=domain.com
#   _zone_id=220
_get_root() {
  domain=$1
  i=1

  if ! _poweradmin_rest "GET" "/api/v${POWERADMIN_API_VERSION}/zones"; then
    _err "Failed to retrieve zones"
    return 1
  fi

  _zones_response="$response"

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)

    if [ -z "$h" ]; then
      _debug "Root domain not found for $domain"
      return 1
    fi

    zone_obj=$(
      printf '%s' "$_zones_response" |
        sed 's/},{/}\n{/g' |
        grep -F "\"name\":\"$h\"" |
        _head_n 1
    )

    if [ -n "$zone_obj" ]; then
      _zone_id=$(printf '%s' "$zone_obj" | _egrep_o '"id":[0-9][0-9]*' | _head_n 1 | cut -d: -f2)
      _domain="$h"
      _debug "Found zone: $_domain with id: $_zone_id"
      return 0
    fi

    i=$(_math "$i" + 1)
  done
}

_poweradmin_rest() {
  method=$1
  ep=$2
  data=$3
  ct=$4

  export _H1="X-API-Key: $POWERADMIN_API_KEY"

  if [ "$method" = "GET" ]; then
    response="$(_get "$POWERADMIN_URL$ep")"
  else
    _debug "API call: $method $ep"
    _debug "Content-Type: $ct"
    _debug "Payload: $data"
    response="$(_post "$data" "$POWERADMIN_URL$ep" "" "$method" "$ct")"
  fi

  # Clear _H1 variable
  unset -v _H1

  if [ "$?" != "0" ]; then
    _err "API error on $method $ep"
    _debug "Response: $response"
    return 1
  fi

  if printf '%s' "$response" | grep -q '"success"[[:space:]]*:[[:space:]]*false'; then
    _err "API reported failure on $method $ep"
    _debug "Response: $response"
    return 1
  fi

  _debug2 "API Response: $response"
  return 0
}
