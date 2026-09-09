#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_optidata_info='Optidata Cloud
Site: console.optidata.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_optidata
Options:
 OPTIDATA_Token DNS API key. Create a key of kind DNS in the Optidata Console (API Keys); it starts with "ocs_".
 OPTIDATA_Api API base URL. Default "https://console.optidata.com".
 OPTIDATA_Location Location code or UUID of the zone. Only needed when the zone lives outside the account default location and the lookup cannot tell. Optional.
 OPTIDATA_Zone_ID Zone ID. Pins the zone and skips the zone lookup. Optional.
Issues: github.com/acmesh-official/acme.sh/issues/7241
Author: Eduardo Langner <https://github.com/optidatacloud>
'

# Port of dnsapi/dns_cf.sh (CloudFlare) to the Optidata Cloud DNS API served by
# ocs-backend. Routes used, all under $OPTIDATA_Api/api/v1 and authenticated
# with the x-api-key header:
#
#   GET    dns-zones?name=<record fqdn>            resolve the zone containing the name
#   GET    dns-zones/<zone_id>                     read one zone (OPTIDATA_Zone_ID)
#   POST   dns-zones/<zone_id>/recordsets          create / upsert the TXT record set
#   DELETE dns-zones/<zone_id>/recordsets?name&type&value   remove one TXT value
#
# Every response is wrapped in {"success":true,"data":...}; errors are flat
# {"status_code":<n>,"message":"...","error":"..."}.

OPTIDATA_DEFAULT_API="https://console.optidata.com"
OPTIDATA_TTL=120
OPTIDATA_MAX_ATTEMPTS=3

########  Public functions #####################

#Usage: dns_optidata_add  _acme-challenge.www.domain.com  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_optidata_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using Optidata Cloud DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _optidata_load_config; then
    return 1
  fi
  _optidata_save_config

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding TXT record $fulldomain"
  # A record set is unique per (name, type) and the apex and wildcard
  # challenges share the same name, so the second value has to be merged into
  # the existing set: that is what upsert does. require_active_zone makes the
  # API fail now (409) instead of queueing a record that would only be
  # published after delegation, long after the ACME server gave up.
  _body="{\"type\":\"TXT\",\"name\":\"$(_optidata_json_escape "$fulldomain")\",\"records\":[\"$(_optidata_json_escape "$txtvalue")\"],\"ttl\":$OPTIDATA_TTL,\"upsert\":true,\"require_active_zone\":true}"
  if _optidata_rest POST "dns-zones/$_domain_id/recordsets$(_optidata_query "")" "$_body"; then
    # The API echoes the whole record set back; the value appears JSON-escaped.
    if printf "%s\n" "$response" | grep -F -- "$(_optidata_json_escape "$txtvalue")" >/dev/null; then
      _info "Added, OK"
      return 0
    fi
    _err "The API accepted the record but the value is missing from the record set: $response"
    return 1
  fi
  _optidata_report_error "Add txt record error."
  return 1
}

#Usage: dns_optidata_rm  _acme-challenge.www.domain.com  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_optidata_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using Optidata Cloud DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _optidata_load_config; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Removing TXT record $fulldomain"
  # Deleting by value keeps the other challenge value (wildcard + apex) in
  # place; the API drops the whole record set once its last value goes away.
  _q="name=$(printf "%s" "$fulldomain" | _url_encode)&type=TXT&value=$(printf "%s" "$txtvalue" | _url_encode)"
  if _optidata_rest DELETE "dns-zones/$_domain_id/recordsets$(_optidata_query "$_q")"; then
    if printf "%s\n" "$response" | tr -d " " | grep '"deleted":true' >/dev/null; then
      _info "Removed, OK"
    else
      _info "Record value not found, nothing to remove."
    fi
    return 0
  fi
  _optidata_report_error "Delete txt record error."
  return 1
}

####################  Private functions below ##################################

# Reads the settings from the environment or from the saved acme.sh config and
# validates them. Shared by add and rm, which run in separate subshells.
_optidata_load_config() {
  OPTIDATA_Token="${OPTIDATA_Token:-$(_readdomainconf OPTIDATA_Token)}"
  OPTIDATA_Token="${OPTIDATA_Token:-$(_readaccountconf_mutable OPTIDATA_Token)}"
  OPTIDATA_Api="${OPTIDATA_Api:-$(_readaccountconf_mutable OPTIDATA_Api)}"
  OPTIDATA_Location="${OPTIDATA_Location:-$(_readdomainconf OPTIDATA_Location)}"
  OPTIDATA_Location="${OPTIDATA_Location:-$(_readaccountconf_mutable OPTIDATA_Location)}"
  OPTIDATA_Zone_ID="${OPTIDATA_Zone_ID:-$(_readdomainconf OPTIDATA_Zone_ID)}"
  OPTIDATA_Zone_ID="${OPTIDATA_Zone_ID:-$(_readaccountconf_mutable OPTIDATA_Zone_ID)}"

  # Keys are pasted with quotes or blanks often enough to be worth cleaning.
  OPTIDATA_Token="$(printf "%s" "$OPTIDATA_Token" | tr -d '" ')"
  if [ -z "$OPTIDATA_Token" ]; then
    OPTIDATA_Token=""
    _err "You did not specify OPTIDATA_Token yet."
    _err "Create a DNS API key in the Optidata Console (API Keys) and export it:"
    _err "export OPTIDATA_Token=ocs_xxxxxxxxxxxxxxxx"
    return 1
  fi
  if ! _startswith "$OPTIDATA_Token" "ocs_"; then
    OPTIDATA_Token=""
    _err 'OPTIDATA_Token must be an Optidata API key: it starts with "ocs_". Did you copy the entire key?'
    return 1
  fi

  OPTIDATA_Api="${OPTIDATA_Api:-$OPTIDATA_DEFAULT_API}"
  OPTIDATA_Api="$(printf "%s\n" "$OPTIDATA_Api" | sed 's:/*$::')"
  case "$OPTIDATA_Api" in
  http://* | https://*) ;;
  *)
    _err "OPTIDATA_Api must be an http(s) URL, e.g. $OPTIDATA_DEFAULT_API"
    return 1
    ;;
  esac
  _debug OPTIDATA_Api "$OPTIDATA_Api"
  _debug OPTIDATA_Location "$OPTIDATA_Location"
  _debug OPTIDATA_Zone_ID "$OPTIDATA_Zone_ID"
  return 0
}

# Persists the settings so renewals work without the environment, following
# dns_cf.sh: with a pinned zone the key lives in the domain config (so a
# zone-restricted key can be used per certificate), otherwise in the account
# config.
_optidata_save_config() {
  if [ "$OPTIDATA_Zone_ID" ]; then
    _savedomainconf OPTIDATA_Token "$OPTIDATA_Token"
    _savedomainconf OPTIDATA_Zone_ID "$OPTIDATA_Zone_ID"
    if [ "$OPTIDATA_Location" ]; then
      _savedomainconf OPTIDATA_Location "$OPTIDATA_Location"
    else
      _cleardomainconf OPTIDATA_Location
    fi
  else
    _saveaccountconf_mutable OPTIDATA_Token "$OPTIDATA_Token"
    if [ "$OPTIDATA_Location" ]; then
      _saveaccountconf_mutable OPTIDATA_Location "$OPTIDATA_Location"
    else
      _clearaccountconf_mutable OPTIDATA_Location
    fi
    _clearaccountconf_mutable OPTIDATA_Zone_ID
    _clearaccountconf OPTIDATA_Zone_ID
  fi

  if [ "$OPTIDATA_Api" != "$OPTIDATA_DEFAULT_API" ]; then
    _saveaccountconf_mutable OPTIDATA_Api "$OPTIDATA_Api"
  else
    _clearaccountconf_mutable OPTIDATA_Api
  fi
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=a86dba58-0043-4cc6-a1bb-69d5e86f3ca3
# _zone_location=3f2b46f2-4f14-44e2-8e21-1b6c17f2a9d1 (empty when the API does not report one)
_get_root() {
  domain=$1
  _domain_lc="$(printf "%s\n" "$domain" | _lower_case | sed 's/\.$//')"
  _domain=""
  _domain_id=""
  _sub_domain=""
  _zone_location=""
  _zone_status=""

  if [ "$OPTIDATA_Zone_ID" ]; then
    _debug "Using the pinned zone" "$OPTIDATA_Zone_ID"
    if ! _optidata_rest GET "dns-zones/$OPTIDATA_Zone_ID$(_optidata_query "")"; then
      _optidata_report_error "Can not read zone $OPTIDATA_Zone_ID."
      return 1
    fi
    _zone_json="$response"
  else
    # The API returns every zone that contains the name, most specific first.
    if ! _optidata_rest GET "dns-zones?name=$(printf "%s" "$_domain_lc" | _url_encode)"; then
      _optidata_report_error "Zone lookup for $domain failed."
      return 1
    fi
    if printf "%s\n" "$response" | tr -d " " | grep '"data":\[\]' >/dev/null; then
      _err "No Optidata DNS zone contains $domain."
      _err "Check that the zone exists in this account and that the API key is allowed to access it."
      return 1
    fi
    # Pick the longest zone that is a suffix of the name ourselves as well, so
    # an API that ignores the name filter still resolves the right zone.
    _zone_json="$(_optidata_pick_zone "$response" "$_domain_lc")"
    if [ -z "$_zone_json" ]; then
      _err "No Optidata DNS zone contains $domain: $response"
      return 1
    fi
  fi

  _domain_id="$(_optidata_json_string "$_zone_json" id)"
  _domain="$(_optidata_json_string "$_zone_json" zone_name)"
  if [ -z "$_domain" ]; then
    _domain="$(_optidata_json_string "$_zone_json" name)"
  fi
  _domain="$(printf "%s\n" "$_domain" | _lower_case | sed 's/\.$//')"
  _zone_location="$(_optidata_json_string "$_zone_json" location)"
  _zone_status="$(_optidata_json_string "$_zone_json" status)"
  _debug _zone_location "$_zone_location"
  _debug _zone_status "$_zone_status"

  if [ -z "$_domain_id" ] || [ -z "$_domain" ]; then
    _err "Could not read the zone id and name from the API response: $response"
    return 1
  fi

  if [ "$_domain_lc" = "$_domain" ]; then
    _sub_domain=""
  else
    case "$_domain_lc" in
    *".$_domain")
      _sub_domain="${_domain_lc%".$_domain"}"
      ;;
    *)
      _err "Zone $_domain ($_domain_id) does not contain $domain."
      return 1
      ;;
    esac
  fi

  if [ "$_zone_status" ] && [ "$_zone_status" != "ACTIVE" ] && ! _contains "$_domain" "internal"; then
    _info "Zone $_domain has status $_zone_status; records are only published once the zone is ACTIVE (delegated to the Optidata name servers)."
  fi
  return 0
}

# Usage: _optidata_pick_zone '<list response>' '<lowercase fqdn>'
# Prints the JSON of the zone with the longest name that is the fqdn itself or
# one of its parents. Zones are flat objects, so splitting on "},{" is safe.
_optidata_pick_zone() {
  _pz_json="$1"
  _pz_name="$2"
  _pz_objects="$(printf "%s\n" "$_pz_json" | sed 's/}, *{/}\
{/g')"
  _pz_count="$(printf "%s\n" "$_pz_objects" | wc -l | tr -d " ")"
  _pz_best=""
  _pz_best_len=0
  _pz_i=1
  while [ "$_pz_i" -le "$_pz_count" ]; do
    _pz_obj="$(printf "%s\n" "$_pz_objects" | sed -n "${_pz_i}p")"
    _pz_zone="$(_optidata_json_string "$_pz_obj" zone_name)"
    if [ -z "$_pz_zone" ]; then
      _pz_zone="$(_optidata_json_string "$_pz_obj" name)"
    fi
    _pz_zone="$(printf "%s\n" "$_pz_zone" | _lower_case | sed 's/\.$//')"
    if [ "$_pz_zone" ]; then
      case "$_pz_name" in
      "$_pz_zone" | *".$_pz_zone")
        if [ "${#_pz_zone}" -gt "$_pz_best_len" ]; then
          _pz_best="$_pz_obj"
          _pz_best_len="${#_pz_zone}"
        fi
        ;;
      esac
    fi
    _pz_i=$(_math "$_pz_i" + 1)
  done
  printf "%s" "$_pz_best"
}

# Usage: _optidata_json_string '<json>' key
# Prints the string value of the first "key" in the JSON, nothing when the key
# is absent or not a string (e.g. "location":null).
_optidata_json_string() {
  printf "%s\n" "$1" | _egrep_o "\"$2\": *\"[^\"]*\"" | _head_n 1 | sed 's/^"[^"]*": *"//; s/"$//'
}

# Escapes a value for use inside a JSON string literal.
_optidata_json_escape() {
  printf "%s\n" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Usage: _optidata_query '<query without the leading ?>'
# Appends the location (explicit OPTIDATA_Location, else the one reported by
# the zone lookup) and prints the query string with its leading "?", or
# nothing when there is nothing to send.
_optidata_query() {
  _oq="$1"
  _oq_loc="${OPTIDATA_Location:-$_zone_location}"
  if [ "$_oq_loc" ]; then
    if [ "$_oq" ]; then
      _oq="$_oq&location=$(printf "%s" "$_oq_loc" | _url_encode)"
    else
      _oq="location=$(printf "%s" "$_oq_loc" | _url_encode)"
    fi
  fi
  if [ "$_oq" ]; then
    printf "?%s" "$_oq"
  fi
}

# Usage: _optidata_rest METHOD 'endpoint under /api/v1' [json body]
# Sets $response to the normalized JSON body. Returns 0 on a success envelope;
# otherwise sets $_optidata_status / $_optidata_message and returns 1. Rate
# limits and upstream hiccups (429, 502-504) are retried a few times.
_optidata_rest() {
  _m=$1
  _ep=$2
  _data=$3
  _debug "$_m $_ep"

  # Hooks share one shell and _get/_post always send _H1 to _H5, so the unused
  # slots have to be cleared: otherwise a previous provider's header (an auth
  # header, for instance) is sent to the Optidata endpoint.
  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  export _H3="x-api-key: $OPTIDATA_Token"
  export _H4=""
  export _H5=""

  _url="$OPTIDATA_Api/api/v1/$_ep"
  _optidata_status=""
  _optidata_message=""
  _attempt=1
  while true; do
    # A failed request leaves the previous status line in the header file, which
    # would then be read as this request's response code.
    if [ -z "$HTTP_HEADER" ]; then
      _err "HTTP header file is not initialized"
      return 1
    fi
    : >"$HTTP_HEADER" || return 1
    if [ "$_m" = "GET" ]; then
      response="$(_get "$_url")"
    else
      _debug2 data "$_data"
      response="$(_post "$_data" "$_url" "" "$_m")"
    fi
    _ret="$?"
    if [ "$_ret" != "0" ]; then
      _err "Request to $_url failed. Is OPTIDATA_Api correct and reachable?"
      return 1
    fi
    _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d '\r\n')"
    _debug "http response code" "$_code"
    response="$(printf "%s\n" "$response" | _normalizeJson)"
    _debug2 response "$response"

    if printf "%s\n" "$response" | tr -d " " | grep '"success":true' >/dev/null; then
      return 0
    fi

    _optidata_status="$(printf "%s\n" "$response" | _egrep_o '"status_code": *[0-9]*' | _head_n 1 | cut -d : -f 2 | tr -d " ")"
    if [ -z "$_optidata_status" ]; then
      _optidata_status="$_code"
    fi
    _optidata_message="$(_optidata_json_string "$response" message)"
    if [ -z "$_optidata_message" ]; then
      # Validation errors carry an array of messages.
      _optidata_message="$(printf "%s\n" "$response" | _egrep_o '"message": *\[[^]]*\]' | _head_n 1 | sed 's/^"message": *\[//; s/\]$//' | tr -d '"')"
    fi

    case "$_optidata_status" in
    429 | 502 | 503 | 504)
      if [ "$_attempt" -lt "$OPTIDATA_MAX_ATTEMPTS" ]; then
        _wait="$(grep -i "^Retry-After:" "$HTTP_HEADER" | _tail_n 1 | cut -d : -f 2 | tr -d ' \r\n')"
        case "$_wait" in
        '' | *[!0-9]*) _wait=5 ;;
        esac
        if [ "$_wait" -gt 60 ]; then
          _wait=60
        fi
        _info "Optidata API answered HTTP $_optidata_status; retrying in ${_wait}s (attempt $_attempt of $OPTIDATA_MAX_ATTEMPTS)."
        _sleep "$_wait"
        _attempt=$(_math "$_attempt" + 1)
        continue
      fi
      ;;
    esac
    return 1
  done
}

# Usage: _optidata_report_error 'what failed'
# Logs the API error captured by _optidata_rest plus a hint for the usual causes.
_optidata_report_error() {
  _err "$1"
  if [ "$_optidata_message" ]; then
    _err "Optidata API answered HTTP ${_optidata_status:-?}: $_optidata_message"
  elif [ "$_optidata_status" ]; then
    _err "Optidata API answered HTTP $_optidata_status: $response"
  fi
  case "$_optidata_status" in
  401)
    _err "Check OPTIDATA_Token: it must be a valid, enabled Optidata API key (it starts with ocs_). Did you copy the entire key?"
    ;;
  402)
    _err "The account is blocked for billing reasons. Check the payment method in the Optidata Console."
    ;;
  403)
    _err "The key must be a DNS API key with the dns_zones scope, the permissions zones_read, records_create, records_update and records_delete, and access to this zone."
    ;;
  404)
    _err "The zone was not found. If it lives outside the account default location, set OPTIDATA_Location to its location code or UUID."
    ;;
  409)
    _err "The zone is not delegated to the Optidata name servers yet. Point the domain NS records to them and retry once the zone status is ACTIVE."
    ;;
  429)
    _err "The Optidata API rate limit was reached. Retry in a minute."
    ;;
  esac
}
