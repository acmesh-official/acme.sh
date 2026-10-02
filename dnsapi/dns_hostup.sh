#!/usr/bin/env sh
# shellcheck disable=SC2034,SC2154

dns_hostup_info='HostUp DNS
Site: hostup.se
Docs: https://developer.hostup.se/
Options:
 HOSTUP_API_KEY     Required. HostUp API key with read:dns + write:dns + read:domains scopes.
 HOSTUP_API_BASE    Optional. Override API base URL (default: https://cloud.hostup.se/api/v2).
 HOSTUP_TTL         Optional. TTL for TXT records (default: 60 seconds).
 HOSTUP_ZONE_ID     Optional. Force a specific v2 zone ID (zone_...) and skip auto-detection.
Author: HostUp (https://cloud.hostup.se/contact/en)
'

HOSTUP_API_BASE_DEFAULT="https://cloud.hostup.se/api/v2"
HOSTUP_DEFAULT_TTL=60

# Public: add TXT record
# Usage: dns_hostup_add _acme-challenge.example.com "txt-value"
dns_hostup_add() {
  fulldomain="$1"
  txtvalue="$2"
  hostup_add_txtvalue="$2"

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
  hostup_add_record_value="$(_hostup_json_escape "$hostup_add_txtvalue")"

  raw_ttl="${HOSTUP_TTL:-$HOSTUP_DEFAULT_TTL}"
  ttl="$(_hostup_normalize_ttl "$raw_ttl")"
  if [ -z "$ttl" ]; then
    _err "HOSTUP_TTL must be a whole number between 60 and 86400 seconds."
    return 1
  fi
  if [ -n "$HOSTUP_TTL" ]; then
    HOSTUP_TTL="$ttl"
    _saveaccountconf_mutable HOSTUP_TTL "$HOSTUP_TTL"
  fi

  _debug "zone_id" "$HOSTUP_ZONE_ID"
  _debug "zone_domain" "$HOSTUP_ZONE_DOMAIN"
  _debug "record_name" "$record_name"
  _debug "ttl" "$ttl"

  record_name_fqdn="$(_hostup_fqdn "$fulldomain")"
  if _hostup_find_record "$HOSTUP_ZONE_ID" "$record_name_fqdn" "$hostup_add_txtvalue"; then
    _info "TXT record already exists for $fulldomain"
    return 0
  fi

  request_body="{\"name\":\"$record_name\",\"type\":\"TXT\",\"value\":\"$hostup_add_record_value\",\"ttl\":$ttl}"

  if ! _hostup_rest "POST" "/dns-zones/$HOSTUP_ZONE_ID/records" "$request_body"; then
    return 1
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

  if ! _hostup_find_record "$HOSTUP_ZONE_ID" "$record_name_fqdn" "$record_value"; then
    _info "TXT record not found for $record_name_fqdn. Skipping removal."
    _hostup_clear_record_id "$HOSTUP_ZONE_ID" "$fulldomain" "$record_value"
    return 0
  fi

  _debug "Deleting record" "$HOSTUP_RECORD_ID"

  if ! _hostup_delete_record_by_id "$HOSTUP_ZONE_ID" "$HOSTUP_RECORD_ID"; then
    return 1
  fi

  _info "Deleted TXT record $HOSTUP_RECORD_ID"
  _hostup_clear_record_id "$HOSTUP_ZONE_ID" "$fulldomain" "$record_value"
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
  HOSTUP_API_BASE="$(_hostup_normalize_api_base "$HOSTUP_API_BASE")"

  if [ -z "$HOSTUP_API_KEY" ]; then
    HOSTUP_API_KEY=""
    _err "HOSTUP_API_KEY is not set."
    _err "Please export your HostUp API key with read:dns, write:dns, and read:domains scopes."
    return 1
  fi

  _saveaccountconf_mutable HOSTUP_API_KEY "$HOSTUP_API_KEY"
  _saveaccountconf_mutable HOSTUP_API_BASE "$HOSTUP_API_BASE"

  if [ -n "$HOSTUP_ZONE_ID" ]; then
    _saveaccountconf_mutable HOSTUP_ZONE_ID "$HOSTUP_ZONE_ID"
  fi

  return 0
}

_hostup_normalize_api_base() {
  api_base="${1%/}"

  case "$api_base" in
  */api/v2)
    printf "%s" "$api_base"
    ;;
  */api)
    printf "%s/v2" "$api_base"
    ;;
  *)
    printf "%s" "$api_base"
    ;;
  esac
}

_hostup_normalize_ttl() {
  ttl_value="$1"

  case "$ttl_value" in
  "" | *[!0-9]*)
    return 1
    ;;
  esac

  while [ "${ttl_value#0}" != "$ttl_value" ]; do
    ttl_value="${ttl_value#0}"
  done
  [ -z "$ttl_value" ] && ttl_value=0

  case "$ttl_value" in
  ??????*)
    return 1
    ;;
  esac

  if [ "$ttl_value" -lt 60 ] || [ "$ttl_value" -gt 86400 ]; then
    return 1
  fi

  printf "%s" "$ttl_value"
}

_hostup_domain_in_zone() {
  host="$(printf "%s" "${1%.}" | _lower_case)"
  zone="$(printf "%s" "${2%.}" | _lower_case)"

  if [ -z "$host" ] || [ -z "$zone" ]; then
    return 1
  fi

  if [ "$host" = "$zone" ]; then
    return 0
  fi

  case "$host" in
  *."$zone")
    return 0
    ;;
  esac

  return 1
}

_hostup_detect_zone() {
  fulldomain="$1"

  if [ -n "$HOSTUP_ZONE_ID" ] && [ -n "$HOSTUP_ZONE_DOMAIN" ]; then
    if _hostup_domain_in_zone "$fulldomain" "$HOSTUP_ZONE_DOMAIN"; then
      return 0
    fi
    _debug "hostup_cached_zone_mismatch" "$HOSTUP_ZONE_DOMAIN"
    HOSTUP_ZONE_ID=""
    HOSTUP_ZONE_DOMAIN=""
  fi

  HOSTUP_ZONE_DOMAIN=""
  _debug "hostup_full_domain" "$fulldomain"

  if [ -n "$HOSTUP_ZONE_ID" ] && [ -z "$HOSTUP_ZONE_DOMAIN" ]; then
    # Attempt to fetch domain name for provided zone ID
    if _hostup_fetch_zone_details "$HOSTUP_ZONE_ID"; then
      if _hostup_domain_in_zone "$fulldomain" "$HOSTUP_ZONE_DOMAIN"; then
        return 0
      fi
      _debug "hostup_forced_zone_mismatch" "$HOSTUP_ZONE_DOMAIN"
    fi
    HOSTUP_ZONE_ID=""
    HOSTUP_ZONE_DOMAIN=""
  fi

  _domain_candidate="$(printf "%s" "${fulldomain%.}" | _lower_case)"
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

  if ! _hostup_rest "GET" "/dns-zones/$zone_id/records" ""; then
    return 1
  fi

  zonedomain="$(_hostup_json_extract "name" "$_hostup_response")"
  if [ -n "$zonedomain" ]; then
    HOSTUP_ZONE_DOMAIN="$zonedomain"
    return 0
  fi

  return 1
}

_hostup_load_zones() {
  if ! _hostup_rest "GET" "/dns-zones?limit=1000" ""; then
    return 1
  fi

  HOSTUP_ZONES_CACHE=""
  data="$(printf "%s" "$_hostup_response" | tr '{' '\n')"

  while IFS= read -r line; do
    case "$line" in
    *'"id"'*'"name"'*)
      zone_id="$(_hostup_json_extract "id" "$line")"
      zone_domain="$(_hostup_json_extract "name" "$line")"
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

  encoded_domain="$(printf "%s" "$lookup_domain" | _url_encode)"
  if _hostup_rest "GET" "/dns-zones?name=$encoded_domain&limit=1" ""; then
    zone_id="$(_hostup_json_extract "id" "$_hostup_response")"
    zone_domain="$(_hostup_json_extract "name" "$_hostup_response")"
    if [ -n "$zone_id" ] && [ -n "$zone_domain" ]; then
      zone_domain_lower="$(printf "%s" "$zone_domain" | _lower_case)"
      if [ "$zone_domain_lower" = "$lookup_domain" ]; then
        _lookup_zone_domain="$zone_domain"
        _lookup_zone_id="$zone_id"
        HOSTUP_ZONE_DOMAIN="$zone_domain"
        HOSTUP_ZONE_ID="$zone_id"
        return 0
      fi
    fi
  fi

  if [ -z "$HOSTUP_ZONES_CACHE" ] && ! _hostup_load_zones; then
    return 1
  fi

  while IFS='|' read -r domain zone_id; do
    [ -z "$domain" ] && continue
    domain_lower="$(printf "%s" "$domain" | _lower_case)"
    if [ "$domain_lower" = "$lookup_domain" ]; then
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
  _hostup_find_zone_id="$1"
  _hostup_find_fqdn="$2"
  _hostup_find_txtvalue="$3"

  _hostup_find_encoded_name="$(printf "%s" "$_hostup_find_fqdn" | _url_encode)"
  if ! _hostup_rest "GET" "/dns-zones/$_hostup_find_zone_id/records?type=TXT&name=$_hostup_find_encoded_name" ""; then
    return 1
  fi

  HOSTUP_RECORD_ID=""
  _hostup_find_records="$(printf "%s" "$_hostup_response" | tr '{' '\n')"

  while IFS= read -r _hostup_find_line; do
    # Normalize line to make TXT value matching reliable
    _hostup_find_line_clean="$(printf "%s" "$_hostup_find_line" | tr -d '\r\n')"
    _hostup_find_line_value_clean="$(printf "%s" "$_hostup_find_line_clean" | sed 's/\\"//g')"

    _hostup_find_record_type="$(_hostup_json_extract "type" "$_hostup_find_line_clean")"
    [ "$_hostup_find_record_type" != "TXT" ] && continue

    _hostup_find_name_value="$(_hostup_json_extract "name" "$_hostup_find_line_clean")"
    _hostup_find_record_value="$(_hostup_json_extract "value" "$_hostup_find_line_value_clean")"

    _debug "hostup_record_raw" "$_hostup_find_record_value"
    if [ "${_hostup_find_record_value#\"}" != "$_hostup_find_record_value" ] && [ "${_hostup_find_record_value%\"}" != "$_hostup_find_record_value" ]; then
      _hostup_find_record_value="${_hostup_find_record_value#\"}"
      _hostup_find_record_value="${_hostup_find_record_value%\"}"
    fi
    if [ "${_hostup_find_record_value#\'}" != "$_hostup_find_record_value" ] && [ "${_hostup_find_record_value%\'}" != "$_hostup_find_record_value" ]; then
      _hostup_find_record_value="${_hostup_find_record_value#\'}"
      _hostup_find_record_value="${_hostup_find_record_value%\'}"
    fi
    _hostup_find_record_value="$(printf "%s" "$_hostup_find_record_value" | tr -d '\r\n')"
    _debug "hostup_record_value" "$_hostup_find_record_value"

    if [ "$_hostup_find_name_value" = "$_hostup_find_fqdn" ] && [ "$_hostup_find_record_value" = "$_hostup_find_txtvalue" ]; then
      _hostup_find_record_id="$(_hostup_json_extract "id" "$_hostup_find_line_clean")"
      if [ -n "$_hostup_find_record_id" ]; then
        HOSTUP_RECORD_ID="$_hostup_find_record_id"
        return 0
      fi
    fi
  done <<EOF
$_hostup_find_records
EOF

  return 1
}

_hostup_json_extract() {
  key="$1"
  input="${2:-$line}"

  # First try to extract quoted values (strings)
  quoted_match="$(printf "%s" "$input" | _egrep_o "\"$key\"[ ]*:[ ]*\"[^\"]*\"" | _head_n 1)"
  if [ -n "$quoted_match" ]; then
    printf "%s" "$quoted_match" |
      cut -d : -f2- |
      sed 's/^[ ]*"//' |
      sed 's/"[ ]*$//' |
      sed 's/\\"/"/g'
    return 0
  fi

  # Fallback for unquoted values (e.g., numeric IDs)
  unquoted_match="$(printf "%s" "$input" | _egrep_o "\"$key\"[ ]*:[ ]*[^,}]*" | _head_n 1)"
  if [ -n "$unquoted_match" ]; then
    printf "%s" "$unquoted_match" |
      cut -d : -f2- |
      tr -d '", 	' |
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
  txtvalue="$3"
  safe_zone="$(printf "%s" "$zone_id" | sed 's/[^A-Za-z0-9]/_/g')"
  safe_domain="$(printf "%s" "$domain" | _lower_case | sed 's/[^a-z0-9]/_/g')"
  if [ -n "$txtvalue" ]; then
    safe_value="$(printf "%s" "$txtvalue" | sed 's/[^A-Za-z0-9]/_/g')"
    printf "%s_%s_%s" "$safe_zone" "$safe_domain" "$safe_value"
    return 0
  fi
  printf "%s_%s" "$safe_zone" "$safe_domain"
}

_hostup_clear_record_id() {
  zone_id="$1"
  domain="$2"
  txtvalue="$3"
  key="$(_hostup_record_key "$zone_id" "$domain" "$txtvalue")"
  _clearaccountconf_mutable "HOSTUP_RECORD_$key"
  legacy_key="$(_hostup_record_key "$zone_id" "$domain")"
  if [ "$legacy_key" != "$key" ]; then
    _clearaccountconf_mutable "HOSTUP_RECORD_$legacy_key"
  fi
}

_hostup_delete_record_by_id() {
  zone_id="$1"
  record_id="$2"

  if ! _hostup_rest "DELETE" "/dns-zones/$zone_id/records/$record_id" ""; then
    return 1
  fi

  return 0
}

_hostup_problem_error() {
  problem_code="$(_hostup_json_extract "code" "$_hostup_response")"
  problem_detail="$(_hostup_json_extract "detail" "$_hostup_response")"

  if [ -n "$problem_detail" ]; then
    if [ -n "$problem_code" ]; then
      _err "HostUp API error ($problem_code): $problem_detail"
    else
      _err "HostUp API error: $problem_detail"
    fi
    return 0
  fi

  return 1
}

_hostup_rest() {
  method="$1"
  route="$2"
  data="$3"

  _hostup_response=""

  export _H1="Authorization: Bearer $HOSTUP_API_KEY"
  export _H2="Accept: application/json"

  if [ "$method" = "GET" ]; then
    _hostup_response="$(_get "$HOSTUP_API_BASE$route")"
  else
    _hostup_response="$(_post "$data" "$HOSTUP_API_BASE$route" "" "$method" "application/json")"
  fi

  ret="$?"

  unset _H1
  unset _H2

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
    _hostup_problem_error || _err "HostUp API returned 401 Unauthorized. Check HOSTUP_API_KEY scopes and IP restrictions."
    return 1
    ;;
  403)
    _hostup_problem_error || _err "HostUp API returned 403 Forbidden. The API key lacks required DNS/domain scopes."
    return 1
    ;;
  404)
    _hostup_problem_error || _err "HostUp API returned 404 Not Found for $route"
    return 1
    ;;
  429)
    _hostup_problem_error || _err "HostUp API rate limit exceeded. Please retry later."
    return 1
    ;;
  *)
    _hostup_problem_error || _err "HostUp API request failed with status $http_status"
    return 1
    ;;
  esac
}
