#!/usr/bin/env sh
# dns_czechia.sh - Czechia/ZONER DNS API for acme.sh (DNS-01)
#
# Endpoint:
#   https://api.czechia.com/api/DNS/<zone>/TXT
# Header:
#   authorizationToken: <token>
# Body:
#   {"hostName":"...","text":"...","ttl":3600,"publishZone":1}
#
# Required env:
#   CZ_AuthorizationToken   (saved to account.conf for automatic renewals)
#   CZ_Zones                zone(s) separated by comma/space, e.g. "example.com" or "example.com,example.net"
#                           For SAN/wildcard, the plugin picks the longest matching zone suffix per-domain.
#
# Optional env (can be saved):
#   CZ_TTL (default 3600)
#   CZ_PublishZone (default 1)
#   CZ_API_BASE (default https://api.czechia.com)
#   CZ_CURL_TIMEOUT (default 30)

dns_czechia_add() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Czechia DNS add TXT for $fulldomain"
  _czechia_load_conf || return 1

  zone="$(_czechia_pick_zone "$fulldomain")" || return 1
  host="$(_czechia_rel_host "$fulldomain" "$zone")" || return 1
  url="$CZ_API_BASE/api/DNS/$zone/TXT"
  body="$(_czechia_build_body "$host" "$txtvalue")"

  _info "Czechia zone: $zone"
  _info "Czechia API URL: $url"
  _info "Czechia hostName: $host"

  _czechia_api_request "POST" "$url" "$body"
}

dns_czechia_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Czechia DNS remove TXT for $fulldomain"
  _czechia_load_conf || return 1

  zone="$(_czechia_pick_zone "$fulldomain")" || return 1
  host="$(_czechia_rel_host "$fulldomain" "$zone")" || return 1
  url="$CZ_API_BASE/api/DNS/$zone/TXT"
  body="$(_czechia_build_body "$host" "$txtvalue")"

  _info "Czechia zone: $zone"
  _info "Czechia API URL: $url"
  _info "Czechia hostName: $host"

  _czechia_api_request "DELETE" "$url" "$body"
}

_czechia_load_conf() {
  CZ_AuthorizationToken="${CZ_AuthorizationToken:-$(_readaccountconf_mutable CZ_AuthorizationToken)}"
  if [ -z "$CZ_AuthorizationToken" ]; then
    _err "CZ_AuthorizationToken is missing."
    _err "Export it first: export CZ_AuthorizationToken=\"...\""
    return 1
  fi
  _saveaccountconf_mutable CZ_AuthorizationToken "$CZ_AuthorizationToken"

  CZ_Zones="${CZ_Zones:-$(_readaccountconf_mutable CZ_Zones)}"
  CZ_TTL="${CZ_TTL:-$(_readaccountconf_mutable CZ_TTL)}"
  CZ_PublishZone="${CZ_PublishZone:-$(_readaccountconf_mutable CZ_PublishZone)}"
  CZ_API_BASE="${CZ_API_BASE:-$(_readaccountconf_mutable CZ_API_BASE)}"
  CZ_CURL_TIMEOUT="${CZ_CURL_TIMEOUT:-$(_readaccountconf_mutable CZ_CURL_TIMEOUT)}"

  if [ -z "$CZ_Zones" ]; then
    _err "CZ_Zones is required (apex zone), e.g. \"example.com\" or \"example.com,example.net\""
    return 1
  fi

  [ -z "$CZ_TTL" ] && CZ_TTL="3600"
  [ -z "$CZ_PublishZone" ] && CZ_PublishZone="1"
  [ -z "$CZ_API_BASE" ] && CZ_API_BASE="https://api.czechia.com"
  [ -z "$CZ_CURL_TIMEOUT" ] && CZ_CURL_TIMEOUT="30"

  CZ_Zones="$(_czechia_norm_zonelist "$CZ_Zones")"
  CZ_API_BASE="$(printf "%s" "$CZ_API_BASE" | sed 's:/*$::')"

  _saveaccountconf_mutable CZ_Zones "$CZ_Zones"
  _saveaccountconf_mutable CZ_TTL "$CZ_TTL"
  _saveaccountconf_mutable CZ_PublishZone "$CZ_PublishZone"
  _saveaccountconf_mutable CZ_API_BASE "$CZ_API_BASE"
  _saveaccountconf_mutable CZ_CURL_TIMEOUT "$CZ_CURL_TIMEOUT"

  return 0
}

_czechia_norm_zonelist() {
  # Normalize comma/space separated list to a single comma-separated list
  # - lowercased
  # - trimmed
  # - trailing dots removed
  # - empty entries dropped
  in="$1"
  [ -z "$in" ] && return 0

  in="$(_lower_case "$in")"

  printf "%s" "$in" |
    tr ' ' ',' |
    tr -s ',' |
    sed 's/[\t\r\n]//g; s/\.$//; s/^,//; s/,$//; s/,,*/,/g'
}

_czechia_pick_zone() {
  fulldomain="$1"

  fd="$(_lower_case "$fulldomain")"
  fd="$(printf "%s" "$fd" | sed 's/\.$//')"

  best=""
  bestlen=0

  oldifs="$IFS"
  IFS=','
  for z in $CZ_Zones; do
    z="$(printf "%s" "$z" | sed 's/^ *//; s/ *$//; s/\.$//')"
    [ -z "$z" ] && continue

    case "$fd" in
    "$z" | *".$z")
      if [ "${#z}" -gt "$bestlen" ]; then
        best="$z"
        bestlen=${#z}
      fi
      ;;
    esac
  done
  IFS="$oldifs"

  if [ -z "$best" ]; then
    _err "No matching zone for '$fd'. Set CZ_Zones to include the apex zone for this domain."
    return 1
  fi

  printf "%s" "$best"
  return 0
}

_czechia_rel_host() {
  fulldomain="$1"
  zone="$2"

  fd="$(_lower_case "$fulldomain")"
  fd="$(printf "%s" "$fd" | sed 's/\.$//')"

  z="$(_lower_case "$zone")"
  z="$(printf "%s" "$z" | sed 's/\.$//')"

  if [ "$fd" = "$z" ]; then
    printf "%s" "@"
    return 0
  fi

  suffix=".$z"
  case "$fd" in
  *"$suffix")
    rel="${fd%"$suffix"}"
    [ -z "$rel" ] && rel="@"
    printf "%s" "$rel"
    return 0
    ;;
  esac

  _err "fulldomain '$fd' is not under zone '$z'"
  return 1
}

_czechia_build_body() {
  host="$1"
  txt="$2"
  txt_escaped="$(_czechia_json_escape "$txt")"
  printf "%s" "{\"hostName\":\"$host\",\"text\":\"$txt_escaped\",\"ttl\":$CZ_TTL,\"publishZone\":$CZ_PublishZone}"
}

_czechia_json_escape() {
  # Minimal JSON escaping for TXT value (backslash + quote)
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_czechia_api_request() {
  method="$1"
  url="$2"
  body="$3"

  export _H1="authorizationToken: $CZ_AuthorizationToken"
  export _H2="Content-Type: application/json"
  export _CURL_TIMEOUT="$CZ_CURL_TIMEOUT"

  _info "Czechia request: $method $url"
  _debug2 "Czechia body: $body"

  resp="$(_post "$body" "$url" "" "$method" "application/json")"
  post_ret="$?"

  if [ "$post_ret" -ne 0 ]; then
    _err "Czechia API call failed (ret=$post_ret). Response: ${resp:-<empty>}"
    return 1
  fi

  _debug2 "Czechia response: ${resp:-<empty>}"
  return 0
}
