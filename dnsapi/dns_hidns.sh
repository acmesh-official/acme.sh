#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_hidns_info='HiDNS
Site: github.com/hihus/hidns
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_hidns
Options:
 HIDNS_Url HiDNS instance base URL (e.g. https://hidns.example.com)
 HIDNS_Token API Token
Issues: github.com/acmesh-official/acme.sh/issues
Author: HINS
'

HIDNS_TTL_DEFAULT=120

# Public: add TXT record
dns_hidns_add() {
  fulldomain="$(_idn "${1}")"
  txtvalue="${2}"

  _info "Using HiDNS API"

  if ! _hidns_init; then
    return 1
  fi

  if ! _hidns_get_root "$fulldomain"; then
    _err "Unable to determine HiDNS zone for $fulldomain"
    return 1
  fi

  _debug "zone_id" "$_HIDNS_ZONE_ID"
  _debug "zone_name" "$_HIDNS_ZONE_NAME"

  record_name="$(printf "%s" "$fulldomain" | sed "s/\\.$_HIDNS_ZONE_NAME\$//")"
  _debug "record_name" "$record_name"

  ttl="${HIDNS_TTL:-$HIDNS_TTL_DEFAULT}"

  body="{\"name\":\"$record_name\",\"type\":\"TXT\",\"value\":\"$txtvalue\",\"ttl\":$ttl}"

  if ! _hidns_request POST "/domains/$_HIDNS_ZONE_ID/records" "$body"; then
    _err "HiDNS API: failed to create TXT record for $fulldomain"
    return 1
  fi

  _HIDNS_RECORD_ID="$(echo "$_hidns_response" | _egrep_o '"id":"[^"]*"' | cut -d: -f2 | tr -d '"')"
  if [ -z "$_HIDNS_RECORD_ID" ]; then
    _HIDNS_RECORD_ID="$(echo "$_hidns_response" | _egrep_o '"id": *[0-9]+' | _head_n 1 | cut -d: -f2 | tr -d ' ')"
  fi
  if [ -n "$_HIDNS_RECORD_ID" ]; then
    _hidns_save_record_id "$_HIDNS_ZONE_ID" "$fulldomain" "$_HIDNS_RECORD_ID"
  fi

  _info "Added TXT record for $fulldomain"
  return 0
}

# Public: remove TXT record
dns_hidns_rm() {
  fulldomain="$(_idn "${1}")"
  txtvalue="${2}"

  _info "Using HiDNS API"

  if ! _hidns_init; then
    return 1
  fi

  if ! _hidns_get_root "$fulldomain"; then
    _err "Unable to determine HiDNS zone for $fulldomain"
    return 1
  fi

  record_id_cached="$(_hidns_get_saved_record_id "$_HIDNS_ZONE_ID" "$fulldomain")"
  if [ -n "$record_id_cached" ]; then
    _debug "using cached record_id" "$record_id_cached"
    if _hidns_request DELETE "/domains/$_HIDNS_ZONE_ID/records/$record_id_cached"; then
      _hidns_clear_record_id "$_HIDNS_ZONE_ID" "$fulldomain"
      _info "Deleted cached TXT record $record_id_cached"
      return 0
    fi
    _debug "cached record deletion failed, falling back to record search"
  fi

  record_name="$(printf "%s" "$fulldomain" | sed "s/\\.$_HIDNS_ZONE_NAME\$//")"
  _debug "record_name" "$record_name"

  if ! _hidns_find_txt_record "$_HIDNS_ZONE_ID" "$record_name" "$txtvalue"; then
    _info "TXT record not found for $fulldomain, nothing to remove"
    return 0
  fi

  _debug "found record_id" "$_HIDNS_FOUND_RECORD_ID"

  if ! _hidns_request DELETE "/domains/$_HIDNS_ZONE_ID/records/$_HIDNS_FOUND_RECORD_ID"; then
    _err "HiDNS API: failed to delete TXT record for $fulldomain"
    return 1
  fi

  _hidns_clear_record_id "$_HIDNS_ZONE_ID" "$fulldomain"
  _info "Deleted TXT record for $fulldomain"
  return 0
}

##############################
# Private helpers

_hidns_init() {
  HIDNS_Url="${HIDNS_Url:-$(_readaccountconf_mutable HIDNS_Url)}"
  HIDNS_Token="${HIDNS_Token:-$(_readaccountconf_mutable HIDNS_Token)}"
  HIDNS_TTL="${HIDNS_TTL:-$(_readaccountconf_mutable HIDNS_TTL)}"

  HIDNS_Url="$(printf "%s" "$HIDNS_Url" | sed 's/\/api\/$//' | sed 's/\/api$//' | sed 's/\/$//')"

  if [ -z "$HIDNS_Url" ]; then
    HIDNS_Url=""
    _err "HIDNS_Url is not set."
    _err "Please export HIDNS_Url as the base URL of your HiDNS instance."
    return 1
  fi

  if [ -z "$HIDNS_Token" ]; then
    HIDNS_Token=""
    _err "HIDNS_Token is not set."
    _err "Please export HIDNS_Token as your HiDNS API Token."
    return 1
  fi

  _saveaccountconf_mutable HIDNS_Url "$HIDNS_Url"
  _saveaccountconf_mutable HIDNS_Token "$HIDNS_Token"

  if [ -n "$HIDNS_TTL" ]; then
    _saveaccountconf_mutable HIDNS_TTL "$HIDNS_TTL"
  fi

  _HIDNS_CACHE_ZONE_ID=""
  _HIDNS_CACHE_ZONE_NAME=""
  _hidns_response=""
  _HIDNS_RECORD_ID=""
  _HIDNS_FOUND_RECORD_ID=""
  _HIDNS_ZONE_ID=""
  _HIDNS_ZONE_NAME=""

  return 0
}

_hidns_request() {
  method="$1"
  route="$2"
  data="$3"

  _hidns_response=""

  export _H1="Authorization: Bearer $HIDNS_Token"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  url="$HIDNS_Url/api$route"
  _debug "request" "$method $url"

  if [ "$method" = "GET" ]; then
    _hidns_response="$(_get "$url")"
  else
    _hidns_response="$(_post "$data" "$url" "" "$method" "application/json")"
  fi

  ret="$?"

  unset _H1
  unset _H2
  unset _H3

  if [ "$ret" != "0" ]; then
    _err "HTTP request failed for $route"
    return 1
  fi

  http_status="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
  _debug2 "HTTP status" "$http_status"
  _debug2 "response" "$_hidns_response"

  case "$http_status" in
  200 | 201 | 204) ;;
  *)
    _err "HiDNS API request failed with HTTP status $http_status"
    return 1
    ;;
  esac

  code="$(echo "$_hidns_response" | _egrep_o '"code":-?[0-9]+' | _head_n 1 | cut -d: -f2 | tr -d ' ')"
  if [ -n "$code" ] && [ "$code" != "0" ]; then
    msg="$(echo "$_hidns_response" | _egrep_o '"msg":"[^"]*"' | _head_n 1 | cut -d: -f2 | tr -d '"')"
    _err "HiDNS API error (code $code): $msg"
    return 1
  fi

  return 0
}

_hidns_get_root() {
  fulldomain="$1"

  _debug "get_root for" "$fulldomain"

  if [ -n "$_HIDNS_CACHE_ZONE_ID" ] && [ -n "$_HIDNS_CACHE_ZONE_NAME" ] && _contains "$fulldomain" "$_HIDNS_CACHE_ZONE_NAME"; then
    _HIDNS_ZONE_ID="$_HIDNS_CACHE_ZONE_ID"
    _HIDNS_ZONE_NAME="$_HIDNS_CACHE_ZONE_NAME"
    _debug "using cached zone" "$_HIDNS_ZONE_NAME ($_HIDNS_ZONE_ID)"
    return 0
  fi

  h="$(printf "%s" "$fulldomain" | tr '[:upper:]' '[:lower:]')"

  _page=1
  _pageSize=200

  while true; do
    if ! _hidns_request GET "/domains?page=$_page&pageSize=$_pageSize"; then
      _err "Failed to fetch domain list from HiDNS"
      return 1
    fi

    raw_data="$(echo "$_hidns_response" | _egrep_o '"data":\{[^}]*"list":\[[^\]]*\]' | sed 's/^"data"://' 2>/dev/null)"
    if [ -z "$raw_data" ]; then
      raw_data="$(echo "$_hidns_response" | _egrep_o '"list":\[.*\]' 2>/dev/null)"
    fi

    names="$(echo "$_hidns_response" | _egrep_o '"name":"[^"]*"' | cut -d: -f2 | tr -d '"')"
    ids="$(echo "$_hidns_response" | _egrep_o '"id":[0-9]+' | cut -d: -f2 | tr -d ' ')"

    _debug2 "found domains" "$(echo "$names" | tr '\n' ' ')"

    _name_idx=1
    _id_idx=1
    for _name in $names; do
      _id="$(echo "$ids" | sed -n "${_id_idx}p")"

      if [ "$h" = "$_name" ] || _endswith "$h" ".$_name"; then
        _HIDNS_ZONE_NAME="$_name"
        _HIDNS_ZONE_ID="$_id"
        _HIDNS_CACHE_ZONE_NAME="$_name"
        _HIDNS_CACHE_ZONE_ID="$_id"
        _debug "matched zone" "$_name ($_id)"
        return 0
      fi

      _name_idx="$((_name_idx + 1))"
      _id_idx="$((_id_idx + 1))"
    done

    total="$(echo "$_hidns_response" | _egrep_o '"total":[0-9]+' | _head_n 1 | cut -d: -f2 | tr -d ' ')"
    _debug2 "total domains" "$total"
    if [ -z "$total" ] || [ "$((_page * _pageSize))" -ge "$total" ] 2>/dev/null; then
      break
    fi

    _page="$((_page + 1))"
  done

  _err "Could not find zone for $fulldomain among HiDNS domains"
  return 1
}

_hidns_find_txt_record() {
  zone_id="$1"
  record_name="$2"
  txtvalue="$3"

  _debug "find_txt_record" "zone=$zone_id name=$record_name value=$txtvalue"

  _page=1
  _pageSize=100

  while true; do
    if ! _hidns_request GET "/domains/$zone_id/records?page=$_page&pageSize=$_pageSize"; then
      return 1
    fi

    names="$(echo "$_hidns_response" | _egrep_o '"name":"[^"]*"' | cut -d: -f2 | tr -d '"')"
    ids_str="$(echo "$_hidns_response" | _egrep_o '"id":"[^"]*"' | cut -d: -f2 | tr -d '"')"
    ids_num="$(echo "$_hidns_response" | _egrep_o '"id":[0-9]+' | cut -d: -f2 | tr -d ' ')"
    values="$(echo "$_hidns_response" | _egrep_o '"value":"[^"]*"' | cut -d: -f2 | tr -d '"')"

    _n_idx=1
    for _n in $names; do
      _id="$(echo "$ids_str" | sed -n "${_n_idx}p")"
      if [ -z "$_id" ]; then
        _id="$(echo "$ids_num" | sed -n "${_n_idx}p")"
      fi
      _val="$(echo "$values" | sed -n "${_n_idx}p")"

      if [ "$_n" = "$record_name" ] && [ "$_val" = "$txtvalue" ]; then
        _HIDNS_FOUND_RECORD_ID="$_id"
        return 0
      fi

      _n_idx="$((_n_idx + 1))"
    done

    total="$(echo "$_hidns_response" | _egrep_o '"total":[0-9]+' | _head_n 1 | cut -d: -f2 | tr -d ' ')"
    if [ -z "$total" ] || [ "$((_page * _pageSize))" -ge "$total" ] 2>/dev/null; then
      break
    fi

    _page="$((_page + 1))"
  done

  _err "TXT record not found: $record_name = $txtvalue"
  return 1
}

_hidns_save_record_id() {
  _saveaccountconf_mutable "_HIDNS_RID_${1}_$2" "$3"
}

_hidns_get_saved_record_id() {
  _readaccountconf_mutable "_HIDNS_RID_${1}_$2"
}

_hidns_clear_record_id() {
  _clearaccountconf "_HIDNS_RID_${1}_$2"
}
