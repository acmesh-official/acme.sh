#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_timeweb_host_info='Timeweb.com
 Virtual hosting DNS API (hosting.timeweb.ru). Not Timeweb Cloud.
Site: hosting.timeweb.ru
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_timeweb_host
Options:
 TWH_Login Account login
 TWH_Password Account password
 TWH_AppKey API key. Request it from Timeweb support.
Issues: github.com/acmesh-official/acme.sh/issues/7400
Author: ARNik <arnik@arnik.ru>
'

TWH_Api="https://api.timeweb.ru"

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_timeweb_host_add() {
  fulldomain=$(printf "%s" "$1" | _lower_case)
  txtvalue=$2

  _debug "dns_timeweb_host_add() $fulldomain"

  _twh_init || return 1

  _saveaccountconf_mutable TWH_Login "$TWH_Login"
  _saveaccountconf_mutable TWH_Password "$TWH_Password"
  _saveaccountconf_mutable TWH_AppKey "$TWH_AppKey"

  _get_root "$fulldomain" || return 1

  if [ -n "$_twh_sub_domain" ]; then
    _twh_body="{\"data\":{\"subdomain\":\"$_twh_sub_domain\",\"value\":\"$txtvalue\"},\"type\":\"TXT\"}"
  else
    _twh_body="{\"data\":{\"value\":\"$txtvalue\"},\"type\":\"TXT\"}"
  fi

  _debug "Adding TXT record to $_twh_domain."

  _twh_api POST "$_twh_zone_url/$_twh_domain/user-records/" "$_twh_body" || return 1

  _info "TXT record has been added."
  return 0
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_timeweb_host_rm() {
  fulldomain=$(printf "%s" "$1" | _lower_case)
  txtvalue=$2

  _debug "dns_timeweb_host_rm() $fulldomain"

  _twh_init || return 1
  _get_root "$fulldomain" || return 1

  if ! _twh_find_txt "$txtvalue"; then
    _info "TXT record with value $txtvalue was not found in $_twh_domain, nothing to remove."
    return 0
  fi

  _debug "Removing TXT record $_twh_record_id from $_twh_domain."

  _twh_api DELETE "$_twh_zone_url/$_twh_domain/user-records/$_twh_record_id/" || return 1

  _info "TXT record has been removed."
  return 0
}

########  Private functions below ##################################

# Read the TWH_* variables, authorize and prepare the API urls
_twh_init() {
  TWH_Login="${TWH_Login:-$(_readaccountconf_mutable TWH_Login)}"
  TWH_Password="${TWH_Password:-$(_readaccountconf_mutable TWH_Password)}"
  TWH_AppKey="${TWH_AppKey:-$(_readaccountconf_mutable TWH_AppKey)}"

  if [ -z "$TWH_Login" ] || [ -z "$TWH_Password" ] || [ -z "$TWH_AppKey" ]; then
    _err "You must export variables: TWH_Login, TWH_Password and TWH_AppKey"
    return 1
  fi

  _twh_account_url="$TWH_Api/v1.2/accounts/$TWH_Login"
  _twh_zone_url="$_twh_account_url/domains"

  _twh_auth || return 1

  return 0
}

# Request a new API token and switch the request headers to it
_twh_auth() {
  _debug "Requesting a Timeweb API token."

  _twh_basic=$(printf "%s:%s" "$TWH_Login" "$TWH_Password" | _base64)

  export _H1="Accept: application/json"
  export _H2="x-app-key: $TWH_AppKey"
  export _H3="Authorization: Basic $_twh_basic"
  export _H4=""
  export _H5=""

  [ -n "$HTTP_HEADER" ] && : >"$HTTP_HEADER"

  if ! _twh_response=$(_post "" "$TWH_Api/v1.2/access"); then
    _err "The authorization request to the Timeweb API failed."
    return 1
  fi

  _twh_code=$(_twh_http_code)

  if [ "$_twh_code" != "200" ]; then
    _err "Timeweb API authorization failed ($_twh_code): $_twh_response"
    return 1
  fi

  TWH_Token=$(printf "%s" "$_twh_response" | _egrep_o '"token" *: *"[^"]*"' | _head_n 1 | cut -d '"' -f4)

  if [ -z "$TWH_Token" ]; then
    _err "Failed to obtain a Timeweb API token: $_twh_response"
    return 1
  fi

  export _H3="Authorization: Bearer $TWH_Token"

  return 0
}

# Print the HTTP status of the last API response
_twh_http_code() {
  if [ -n "$HTTP_HEADER" ] && [ -f "$HTTP_HEADER" ]; then
    grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d ' ' -f 2 | tr -d '\r\n'
  fi
}

# Usage: _twh_api GET|POST|DELETE [url] [body]
# Stores the response body in _twh_response
_twh_api() {
  _twh_method=$1
  _twh_endpoint=$2
  _twh_req_body=$3
  _twh_code=""
  _twh_response=""

  _debug "_twh_api" "$_twh_method $_twh_endpoint"
  _debug2 "_twh_req_body" "$_twh_req_body"

  [ -n "$HTTP_HEADER" ] && : >"$HTTP_HEADER"

  if [ "$_twh_method" = "GET" ]; then
    _twh_response=$(_get "$_twh_endpoint")
  else
    _twh_response=$(_post "$_twh_req_body" "$_twh_endpoint" "" "$_twh_method" "application/json")
  fi

  if [ $? -ne 0 ]; then
    _err "The request to the Timeweb API failed: $_twh_response"
    return 1
  fi

  _twh_code=$(_twh_http_code)

  if ! _startswith "$_twh_code" "2"; then
    _err "Timeweb API error ($_twh_code): $_twh_response"
    return 1
  fi

  if _contains "$_twh_response" '"error_code"' || _contains "$_twh_response" '"error_msg"'; then
    _err "Timeweb API error: $_twh_response"
    return 1
  fi

  _debug2 "_twh_response" "$_twh_response"

  return 0
}

# Usage: _get_root _acme-challenge.www.domain.com
# Returns:
# _twh_domain=domain.com
# _twh_sub_domain=_acme-challenge.www
_get_root() {
  _twh_fulldomain=$1
  _twh_domain=""
  _twh_sub_domain=""

  _twh_api GET "$_twh_zone_url" || return 1

  _twh_zones=$(printf "%s" "$_twh_response" | tr ',' '\n' | _egrep_o '"[^"]*"' | tr -d '"' | _lower_case)

  while IFS= read -r _twh_zone; do
    [ -z "$_twh_zone" ] && continue

    if [ "$_twh_fulldomain" = "$_twh_zone" ] ||
      [ "${_twh_fulldomain%."$_twh_zone"}" != "$_twh_fulldomain" ]; then
      [ "${#_twh_zone}" -gt "${#_twh_domain}" ] && _twh_domain=$_twh_zone
    fi
  done <<EOF
$_twh_zones
EOF

  if [ -z "$_twh_domain" ]; then
    _err "Can't find the root domain for $_twh_fulldomain in the Timeweb account."
    return 1
  fi

  if [ "$_twh_domain" = "$_twh_fulldomain" ]; then
    _twh_sub_domain=""
  else
    _twh_sub_domain=${_twh_fulldomain%."$_twh_domain"}
  fi

  _debug "_twh_domain" "$_twh_domain"
  _debug "_twh_sub_domain" "$_twh_sub_domain"

  return 0
}

# Usage: _twh_find_txt [txtvalue]
# Sets _twh_record_id to the id of the TXT record with that value in _twh_sub_domain
_twh_find_txt() {
  _twh_search_value=$1
  _twh_record_id=""
  _twh_page_size=100
  _twh_offset=0

  while true; do
    _twh_api GET "$_twh_zone_url/$_twh_domain/user-records?limit=$_twh_page_size&offset=$_twh_offset" || return 1

    _twh_page=$(_twh_split_records "$_twh_response")

    [ -z "$_twh_page" ] && return 1

    _twh_count=$(printf "%s\n" "$_twh_page" | sed -n '$=')

    while IFS= read -r _twh_record; do
      [ -z "$_twh_record" ] && continue

      _contains "$_twh_record" '"type":"TXT"' || continue

      _twh_record_value=$(printf "%s" "$_twh_record" | _egrep_o '"value":"[^"]*"' | _head_n 1 | cut -d '"' -f4)
      [ "$_twh_record_value" = "$_twh_search_value" ] || continue

      if [ -n "$_twh_sub_domain" ]; then
        _contains "$_twh_record" "\"subdomain\":\"$_twh_sub_domain\"" || continue
      elif _contains "$_twh_record" '"subdomain"' && ! _contains "$_twh_record" '"subdomain":null'; then
        continue
      fi

      _twh_record_id=$(printf "%s" "$_twh_record" | _egrep_o '"id":[0-9][0-9]*' | _head_n 1 | cut -d: -f2)
      [ -n "$_twh_record_id" ] && return 0
    done <<EOF
$_twh_page
EOF

    [ "$_twh_count" -lt "$_twh_page_size" ] && return 1

    _twh_offset=$(_math "$_twh_offset" + "$_twh_page_size")
  done
}

# Usage: _twh_split_records [json_array]
# Prints one JSON record per line
_twh_split_records() {
  printf "%s" "$1" |
    tr -d '\r\n' |
    sed 's/^ *\[//; s/\] *$//; s/" *: */":/g; s/} *, *{/}|{/g' |
    tr '|' '\n'
}
