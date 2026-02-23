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
#   CZ_Zone                 (default apex zone), e.g. example.com
#     - for multi-domain SAN, use CZ_Zones (see below)
#
# Optional env (multi-zone):
#   CZ_Zones  list of zones separated by comma/space, e.g. "example.com,example.net"
#            For DNS-01 SAN, the plugin picks the longest matching zone suffix per-domain.
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
  # token must be available for automatic renewals (read from env or account.conf)
  CZ_AuthorizationToken="${CZ_AuthorizationToken:-$(_readaccountconf_mutable CZ_AuthorizationToken)}"
  if [ -z "$CZ_AuthorizationToken" ]; then
    CZ_AuthorizationToken=""
    _err "CZ_AuthorizationToken is missing."
    _err "Export it first: export CZ_AuthorizationToken=\"...\""
    return 1
  fi
  _saveaccountconf_mutable CZ_AuthorizationToken "$CZ_AuthorizationToken"

  # other settings can be env or saved
  CZ_Zone="${CZ_Zone:-$(_readaccountconf_mutable CZ_Zone)}"
  CZ_Zones="${CZ_Zones:-$(_readaccountconf_mutable CZ_Zones)}"
  CZ_TTL="${CZ_TTL:-$(_readaccountconf_mutable CZ_TTL)}"
  CZ_PublishZone="${CZ_PublishZone:-$(_readaccountconf_mutable CZ_PublishZone)}"
  CZ_API_BASE="${CZ_API_BASE:-$(_readaccountconf_mutable CZ_API_BASE)}"
  CZ_CURL_TIMEOUT="${CZ_CURL_TIMEOUT:-$(_readaccountconf_mutable CZ_CURL_TIMEOUT)}"

  # at least one zone source must be provided
  if [ -z "$CZ_Zone" ] && [ -z "$CZ_Zones" ]; then
    _err "CZ_Zone or CZ_Zones is required (apex zone), e.g. example.com or \"example.com,example.net\""
    return 1
  fi

  [ -z "$CZ_TTL" ] && CZ_TTL="3600"
  [ -z "$CZ_PublishZone" ] && CZ_PublishZone="1"
  [ -z "$CZ_API_BASE" ] && CZ_API_BASE="https://api.czechia.com"
  [ -z "$CZ_CURL_TIMEOUT" ] && CZ_CURL_TIMEOUT="30"

  # normalize
  CZ_Zone="$(printf "%s" "$CZ_Zone" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//')"
  CZ_Zones="$(_czechia_norm_zonelist "$CZ_Zones")"
  CZ_API_BASE="$(printf "%s" "$CZ_API_BASE" | sed 's:/*$::')"

  # persist non-secret config
  _saveaccountconf_mutable CZ_Zone "$CZ_Zone"
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
  fd="$(printf "%s" "$fulldomain" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//')"

  best=""
  bestlen=0

  # 1) CZ_Zone as default (only if it matches)
  if [ -n "$CZ_Zone" ]; then
    z="$CZ_Zone"
    case "$fd" in
    "$z" | *".$z")
      best="$z"
      bestlen=${#z}
      ;;
    esac
  fi

  # 2) CZ_Zones list (longest matching suffix wins)
  if [ -n "$CZ_Zones" ]; then
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
  fi

  if [ -z "$best" ]; then
    _err "No matching zone for '$fd'. Set CZ_Zone or CZ_Zones to include the apex zone for this domain."
    return 1
  fi

  echo "$best"
  return 0
}

_czechia_rel_host() {
  fulldomain="$1"
  zone="$2"

  fd="$(printf "%s" "$fulldomain" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//')"
  z="$(printf "%s" "$zone" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//')"

  if [ "$fd" = "$z" ]; then
    echo "@"
    return 0
  fi

  suffix=".$z"
  case "$fd" in
  *"$suffix")
    rel="${fd%"$suffix"}"
    [ -z "$rel" ] && rel="@"
    echo "$rel"
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
  echo "{\"hostName\":\"$host\",\"text\":\"$txt_escaped\",\"ttl\":$CZ_TTL,\"publishZone\":$CZ_PublishZone}"
}

_czechia_json_escape() {
  echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_czechia_api_request() {
  method="$1"
  url="$2"
  body="$3"

  export _H1="authorizationToken: $CZ_AuthorizationToken"
  export _H2="Content-Type: application/json"

  _info "Czechia request: $method $url"
  _debug2 "Czechia body: $body"

  # _post() can do POST/PUT/DELETE; see DNS-API-Dev-Guide
  resp="$(_post "$body" "$url" "" "$method" "application/json")"
  post_ret="$?"

  if [ "$post_ret" -ne 0 ]; then
    _err "Czechia API call failed (ret=$post_ret). Response: ${resp:-<empty>}"
    return 1
  fi

  _debug2 "Czechia response: ${resp:-<empty>}"
  return 0
}
