#!/usr/bin/env sh
# shellcheck disable=SC2034,SC2154

dns_hostup_info='HostUp DNS
Site: hostup.se
Docs: https://developer.hostup.se/
Options:
 HOSTUP_API_KEY     Required. HostUp API key with read:dns + write:dns + read:domains scopes.
 HOSTUP_API_BASE    Optional. Override API base URL (default: https://cloud.hostup.se/api).
 HOSTUP_TTL         Optional. TTL for TXT records (default: 60 seconds).
 HOSTUP_ZONE_ID     Optional. Force a specific zone ID (skip auto-detection).
Author: HostUp (https://cloud.hostup.se/contact/en)
'

HOSTUP_API_BASE_DEFAULT="https://cloud.hostup.se/api"
HOSTUP_DEFAULT_TTL=60

# Public: add TXT record
# Usage: dns_hostup_add _acme-challenge.example.com "txt-value"
dns_hostup_add() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Using HostUp DNS API"

  if ! _hostup_init; then
    return 1
  fi

  if ! _hostup_detect_zone "$fulldomain"; then
    _err "Unable to determine HostUp zone for $fulldomain"
    return 1
  fi

  record_name="$(_hostup_record_name "$fulldomain" "$HOSTUP_ZONE_DOMAIN")"
  record_name="$(_hostup_sanitize_name "$record_name")"
  record_value="$(_hostup_json_escape "$txtvalue")"

  ttl="${HOSTUP_TTL:-$HOSTUP_DEFAULT_TTL}"

  _debug "zone_id" "$HOSTUP_ZONE_ID"
  _debug "zone_domain" "$HOSTUP_ZONE_DOMAIN"
  _debug "record_name" "$record_name"
  _debug "ttl" "$ttl"

  request_body="{\"name\":\"$record_name\",\"type\":\"TXT\",\"value\":\"$record_value\",\"ttl\":$ttl}"

  if ! _hostup_rest "POST" "/dns/zones/$HOSTUP_ZONE_ID/records" "$request_body"; then
    return 1
  fi

  if ! _contains "$_hostup_response" '"success":true'; then
    _err "HostUp DNS API: failed to create TXT record for $fulldomain"
    _debug2 "_hostup_response" "$_hostup_response"
    return 1
  fi

  record_id="$(_hostup_extract_record_id "$_hostup_response")"
  if [ -n "$record_id" ]; then
    _hostup_save_record_id "$HOSTUP_ZONE_ID" "$fulldomain" "$record_id"
    _debug "hostup_saved_record_id" "$record_id"
  fi

  _info "Added TXT record for $fulldomain"
  return 0
}

# Public: remove TXT record
# Usage: dns_hostup_rm _acme-challenge.example.com "txt-value"
dns_hostup_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Using HostUp DNS API"

  if ! _hostup_init; then
    return 1
  fi

  if ! _hostup_detect_zone "$fulldomain"; then
    _err "Unable to determine HostUp zone for $fulldomain"
    return 1
  fi

  record_name_fqdn="$(_hostup_fqdn "$fulldomain")"
  record_value="$txtvalue"

  record_id_cached="$(_hostup_get_saved_record_id "$HOSTUP_ZONE_ID" "$fulldomain")"
  if [ -n "$record_id_cached" ]; then
    _debug "hostup_record_id_cached" "$record_id_cached"
    if _hostup_delete_record_by_id "$HOSTUP_ZONE_ID" "$record_id_cached"; then
      _info "Deleted TXT record $record_id_cached"
      _hostup_clear_record_id "$HOSTUP_ZONE_ID" "$fulldomain"
      HOSTUP_ZONE_ID=""
      return 0
    fi
  fi

  if ! _hostup_find_record "$HOSTUP_ZONE_ID" "$record_name_fqdn" "$record_value"; then
    _info "TXT record not found for $record_name_fqdn. Skipping removal."
    _hostup_clear_record_id "$HOSTUP_ZONE_ID" "$fulldomain"
    return 0
  fi

  _debug "Deleting record" "$HOSTUP_RECORD_ID"

  if ! _hostup_delete_record_by_id "$HOSTUP_ZONE_ID" "$HOSTUP_RECORD_ID"; then
    return 1
  fi

  _info "Deleted TXT record $HOSTUP_RECORD_ID"
  _hostup_clear_record_id "$HOSTUP_ZONE_ID" "$fulldomain"
  HOSTUP_ZONE_ID=""
  return 0
}

##########################
# Private helper methods #
##########################

_hostup_init() {
  HOSTUP_API_KEY="${HOSTUP_API_KEY:-$(_readaccountconf_mutable HOSTUP_API_KEY)}"
  HOSTUP_API_BASE="${HOSTUP_API_BASE:-$(_readaccountconf_mutable HOSTUP_API_BASE)}"
  HOSTUP_TTL="${HOSTUP_TTL:-$(_readaccountconf_mutable HOSTUP_TTL)}"
  HOSTUP_ZONE_ID="${HOSTUP_ZONE_ID:-$(_readaccountconf_mutable HOSTUP_ZONE_ID)}"

  if [ -z "$HOSTUP_API_BASE" ]; then
    HOSTUP_API_BASE="$HOSTUP_API_BASE_DEFAULT"
  fi

  if [ -z "$HOSTUP_API_KEY" ]; then
    HOSTUP_API_KEY=""
    _err "HOSTUP_API_KEY is not set."
    _err "Please export your HostUp API key with read:dns and write:dns scopes."
    return 1
  fi

  _saveaccountconf_mutable HOSTUP_API_KEY "$HOSTUP_API_KEY"
  _saveaccountconf_mutable HOSTUP_API_BASE "$HOSTUP_API_BASE"

  if [ -n "$HOSTUP_TTL" ]; then
    _saveaccountconf_mutable HOSTUP_TTL "$HOSTUP_TTL"
  fi

  if [ -n "$HOSTUP_ZONE_ID" ]; then
    _saveaccountconf_mutable HOSTUP_ZONE_ID "$HOSTUP_ZONE_ID"
  fi

  return 0
}

_hostup_detect_zone() {
  fulldomain="$1"

  if [ -n "$HOSTUP_ZONE_ID" ] && [ -n "$HOSTUP_ZONE_DOMAIN" ]; then
    return 0
  fi

  HOSTUP_ZONE_DOMAIN=""
  _debug "hostup_full_domain" "$fulldomain"

  if [ -n "$HOSTUP_ZONE_ID" ] && [ -z "$HOSTUP_ZONE_DOMAIN" ]; then
    # Attempt to fetch domain name for provided zone ID
    if _hostup_fetch_zone_details "$HOSTUP_ZONE_ID"; then
      return 0
    fi
    HOSTUP_ZONE_ID=""
  fi

  if ! _hostup_load_zones; then
    return 1
  fi

  _domain_candidate="$(printf "%s" "$fulldomain" | _lower_case)"
  _debug "hostup_initial_candidate" "$_domain_candidate"

  while [ -n "$_domain_candidate" ]; do
    _debug "hostup_zone_candidate" "$_domain_candidate"
    if _hostup_lookup_zone "$_domain_candidate"; then
      HOSTUP_ZONE_DOMAIN="$_lookup_zone_domain"
      HOSTUP_ZONE_ID="$_lookup_zone_id"
      return 0
    fi

    case "$_domain_candidate" in
    *.*) ;;
    *) break ;;
    esac

    _domain_candidate="${_domain_candidate#*.}"
  done

  HOSTUP_ZONE_ID=""
  return 1
}

_hostup_record_name() {
  fulldomain="$1"
  zonedomain="$2"

  # Remove trailing dot, if any
  fulldomain="${fulldomain%.}"
  zonedomain="${zonedomain%.}"

  if [ "$fulldomain" = "$zonedomain" ]; then
    printf "%s" "@"
    return 0
  fi

  suffix=".$zonedomain"
  case "$fulldomain" in
  *"$suffix")
    printf "%s" "${fulldomain%"$suffix"}"
    ;;
  *)
    # Domain not within zone, fall back to full host
    printf "%s" "$fulldomain"
    ;;
  esac
}

_hostup_sanitize_name() {
  name="$1"

  if [ -z "$name" ] || [ "$name" = "." ]; then
    printf "%s" "@"
    return 0
  fi

  # Remove any trailing dot
  name="${name%.}"
  printf "%s" "$name"
}

_hostup_fqdn() {
  domain="$1"
  printf "%s" "${domain%.}"
}

_hostup_fetch_zone_details() {
  zone_id="$1"

  if ! _hostup_rest "GET" "/dns/zones/$zone_id/records" ""; then
    return 1
  fi

  zonedomain="$(printf "%s" "$_hostup_response" | _egrep_o '"domain":"[^"]*"' | sed -n '1p' | cut -d ':' -f 2 | tr -d '"')"
  if [ -n "$zonedomain" ]; then
    HOSTUP_ZONE_DOMAIN="$zonedomain"
    return 0
  fi

  return 1
}

_hostup_load_zones() {
  if ! _hostup_rest "GET" "/dns/zones" ""; then
    return 1
  fi

  HOSTUP_ZONES_CACHE=""
  data="$(printf "%s" "$_hostup_response" | tr '{' '\n')"

  while IFS= read -r line; do
    case "$line" in
    *'"domain_id"'*'"domain"'*)
      zone_id="$(printf "%s" "$line" | _hostup_json_extract "domain_id")"
      zone_domain="$(printf "%s" "$line" | _hostup_json_extract "domain")"
      if [ -n "$zone_id" ] && [ -n "$zone_domain" ]; then
        HOSTUP_ZONES_CACHE="${HOSTUP_ZONES_CACHE}${zone_domain}|${zone_id}
"
        _debug "hostup_zone_loaded" "$zone_domain|$zone_id"
      fi
      ;;
    esac
  done <<EOF
$data
EOF

  if [ -z "$HOSTUP_ZONES_CACHE" ]; then
    _err "HostUp DNS API: no zones returned for the current API key."
    return 1
  fi

  return 0
}

_hostup_lookup_zone() {
  lookup_domain="$1"
  _lookup_zone_id=""
  _lookup_zone_domain=""

  while IFS='|' read -r domain zone_id; do
    [ -z "$domain" ] && continue
    if [ "$domain" = "$lookup_domain" ]; then
      _lookup_zone_domain="$domain"
      _lookup_zone_id="$zone_id"
      HOSTUP_ZONE_DOMAIN="$domain"
      HOSTUP_ZONE_ID="$zone_id"
      return 0
    fi
  done <<EOF
$HOSTUP_ZONES_CACHE
EOF

  return 1
}

_hostup_find_record() {
  zone_id="$1"
  fqdn="$2"
  txtvalue="$3"

  if ! _hostup_rest "GET" "/dns/zones/$zone_id/records" ""; then
    return 1
  fi

  HOSTUP_RECORD_ID=""
  records="$(printf "%s" "$_hostup_response" | tr '{' '\n')"

  while IFS= read -r line; do
    # Normalize line to make TXT value matching reliable
    line_clean="$(printf "%s" "$line" | tr -d '\r\n')"
    line_value_clean="$(printf "%s" "$line_clean" | sed 's/\\"//g')"

    case "$line_clean" in
    *'"type":"TXT"'*'"name"'*'"value"'*)
      name_value="$(_hostup_json_extract "name" "$line_clean")"
      record_value="$(_hostup_json_extract "value" "$line_value_clean")"

      _debug "hostup_record_raw" "$record_value"
      if [ "${record_value#\"}" != "$record_value" ] && [ "${record_value%\"}" != "$record_value" ]; then
        record_value="${record_value#\"}"
        record_value="${record_value%\"}"
      fi
      if [ "${record_value#\'}" != "$record_value" ] && [ "${record_value%\'}" != "$record_value" ]; then
        record_value="${record_value#\'}"
        record_value="${record_value%\'}"
      fi
      record_value="$(printf "%s" "$record_value" | tr -d '\r\n')"
      _debug "hostup_record_value" "$record_value"

      if [ "$name_value" = "$fqdn" ] && [ "$record_value" = "$txtvalue" ]; then
        record_id="$(_hostup_json_extract "id" "$line_clean")"
        if [ -n "$record_id" ]; then
          HOSTUP_RECORD_ID="$record_id"
          return 0
        fi
      fi
      ;;
    esac
  done <<EOF
$records
EOF

  return 1
}

_hostup_json_extract() {
  key="$1"
  input="${2:-$line}"

  # First try to extract quoted values (strings)
  quoted_match="$(printf "%s" "$input" | _egrep_o "\"$key\":\"[^\"]*\"" | _head_n 1)"
  if [ -n "$quoted_match" ]; then
    printf "%s" "$quoted_match" |
      cut -d : -f2- |
      sed 's/^"//' |
      sed 's/"$//' |
      sed 's/\\"/"/g'
    return 0
  fi

  # Fallback for unquoted values (e.g., numeric IDs)
  unquoted_match="$(printf "%s" "$input" | _egrep_o "\"$key\":[^,}]*" | _head_n 1)"
  if [ -n "$unquoted_match" ]; then
    printf "%s" "$unquoted_match" |
      cut -d : -f2- |
      tr -d '", ' |
      tr -d '\r\n'
    return 0
  fi

  return 1
}

_hostup_json_escape() {
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_hostup_record_key() {
  zone_id="$1"
  domain="$2"
  safe_zone="$(printf "%s" "$zone_id" | sed 's/[^A-Za-z0-9]/_/g')"
  safe_domain="$(printf "%s" "$domain" | _lower_case | sed 's/[^a-z0-9]/_/g')"
  printf "%s_%s" "$safe_zone" "$safe_domain"
}

_hostup_save_record_id() {
  zone_id="$1"
  domain="$2"
  record_id="$3"
  key="$(_hostup_record_key "$zone_id" "$domain")"
  _saveaccountconf_mutable "HOSTUP_RECORD_$key" "$record_id"
}

_hostup_get_saved_record_id() {
  zone_id="$1"
  domain="$2"
  key="$(_hostup_record_key "$zone_id" "$domain")"
  _readaccountconf_mutable "HOSTUP_RECORD_$key"
}

_hostup_clear_record_id() {
  zone_id="$1"
  domain="$2"
  key="$(_hostup_record_key "$zone_id" "$domain")"
  _clearaccountconf_mutable "HOSTUP_RECORD_$key"
}

_hostup_extract_record_id() {
  record_id="$(_hostup_json_extract "id" "$1")"
  if [ -n "$record_id" ]; then
    printf "%s" "$record_id"
    return 0
  fi

  printf "%s" "$1" | _egrep_o '"id":[0-9]+' | _head_n 1 | cut -d: -f2
}

_hostup_delete_record_by_id() {
  zone_id="$1"
  record_id="$2"

  if ! _hostup_rest "DELETE" "/dns/zones/$zone_id/records/$record_id" ""; then
    return 1
  fi

  if ! _contains "$_hostup_response" '"success":true'; then
    return 1
  fi

  return 0
}

_hostup_rest() {
  method="$1"
  route="$2"
  data="$3"

  _hostup_response=""

  export _H1="Authorization: Bearer $HOSTUP_API_KEY"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  if [ "$method" = "GET" ]; then
    _hostup_response="$(_get "$HOSTUP_API_BASE$route")"
  else
    _hostup_response="$(_post "$data" "$HOSTUP_API_BASE$route" "" "$method" "application/json")"
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
  _debug2 "_hostup_response" "$_hostup_response"

  case "$http_status" in
  200 | 201 | 204) return 0 ;;
  401)
    _err "HostUp API returned 401 Unauthorized. Check HOSTUP_API_KEY scopes and IP restrictions."
    return 1
    ;;
  403)
    _err "HostUp API returned 403 Forbidden. The API key lacks required DNS scopes."
    return 1
    ;;
  404)
    _err "HostUp API returned 404 Not Found for $route"
    return 1
    ;;
  429)
    _err "HostUp API rate limit exceeded. Please retry later."
    return 1
    ;;
  *)
    _err "HostUp API request failed with status $http_status"
    return 1
    ;;
  esac
}
