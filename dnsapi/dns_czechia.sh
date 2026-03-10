#!/usr/bin/env sh

# dns_czechia.sh - CZECHIA.COM/ZONER DNS API for acme.sh (DNS-01)
#
# Documentation: https://api.czechia.com/swagger/index.html

#shellcheck disable=SC2034
dns_czechia_info='[
  {"name":"CZ_AuthorizationToken","usage":"Your API token from CZECHIA.COM/Zoner administration.","required":"1"},
  {"name":"CZ_Zones","usage":"Managed zones separated by comma or space (e.g. \"example.com\").","required":"1"},
  {"name":"CZ_API_BASE","usage":"Defaults to https://api.czechia.com","required":"0"}
]'

dns_czechia_add() {
  _info "DEBUG: Entering dns_czechia_add for $1"
  fulldomain="$1"
  txtvalue="$2"
  _czechia_load_conf || return 1
  _current_zone=$(_czechia_pick_zone "$fulldomain")
  if [ -z "$_current_zone" ]; then
    _err "No matching zone found for $fulldomain. Please check CZ_Zones."
    return 1
  fi
  _cz=$(printf "%s" "$_current_zone" | _lower_case | sed 's/ //g')
  _tk=$(printf "%s" "$CZ_AuthorizationToken" | sed 's/ //g')
  if [ -z "$_cz" ] || [ -z "$_tk" ]; then
    _err "Missing zone or Token."
    return 1
  fi
  _url="$CZ_API_BASE/api/DNS/$_cz/TXT"
  _fd=$(printf "%s" "$fulldomain" | _lower_case | sed 's/\.$//')

  if [ "$_fd" = "$_cz" ]; then
    _h="@"
  else
    _h=$(printf "%s" "$_fd" | sed "s/\.$_cz$//")
    [ "$_h" = "$_fd" ] && _h="@"
  fi
  [ -z "$_h" ] && _h="@"

  _info "Adding TXT record for $_h in zone $_cz"
  _h_esc=$(printf "%s" "$_h" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _txt_esc=$(printf "%s" "$txtvalue" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _body="{\"hostName\":\"$_h_esc\",\"text\":\"$_txt_esc\",\"ttl\":60,\"publishZone\":1}"

  _debug "URL: $_url"
  _debug "Body: $_body"

  export _H1="Content-Type: application/json"
  export _H2="AuthorizationToken: $_tk"

  if ! _res="$(_post "$_body" "$_url" "" "POST")"; then
    _err "API request failed."
    return 1
  fi
  _debug2 "Response: $_res"

  if _contains "$_res" "already exists"; then
    _info "Record already exists, skipping."
    return 0
  fi

  if _contains "$_res" "\"status\":4" || _contains "$_res" "\"status\":5" || _contains "$_res" "\"errors\""; then
    _err "API error: $_res"
    return 1
  fi
  return 0
}

dns_czechia_rm() {
  fulldomain="$1"
  txtvalue="$2"
  _czechia_load_conf || return 1
  _current_zone=$(_czechia_pick_zone "$fulldomain")
  [ -z "$_current_zone" ] && return 1
  _cz=$(printf "%s" "$_current_zone" | _lower_case | sed 's/ //g')
  _tk=$(printf "%s" "$CZ_AuthorizationToken" | sed 's/ //g')
  _url="$CZ_API_BASE/api/DNS/$_cz/TXT"
  _fd=$(printf "%s" "$fulldomain" | _lower_case | sed 's/\.$//')
  if [ "$_fd" = "$_cz" ]; then
    _h="@"
  else
    _h=$(printf "%s" "$_fd" | sed "s/\.$_cz$//")
    [ "$_h" = "$_fd" ] && _h="@"
  fi
  [ -z "$_h" ] && _h="@"

  _h_esc=$(printf "%s" "$_h" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _txt_esc=$(printf "%s" "$txtvalue" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _body="{\"hostName\":\"$_h_esc\",\"text\":\"$_txt_esc\",\"ttl\":60,\"publishZone\":1}"

  _debug "URL: $_url"
  _debug "Body: $_body"

  export _H1="Content-Type: application/json"
  export _H2="AuthorizationToken: $_tk"
  
  _res="$(_post "$_body" "$_url" "" "DELETE")"
  _debug2 "Response: $_res"
  return 0
}

_czechia_load_conf() {
  CZ_AuthorizationToken="${CZ_AuthorizationToken:-$(_readaccountconf_mutable CZ_AuthorizationToken)}"
  [ -z "$CZ_AuthorizationToken" ] && _err "Missing CZ_AuthorizationToken" && return 1
  CZ_Zones="${CZ_Zones:-$(_readaccountconf_mutable CZ_Zones)}"
  [ -z "$CZ_Zones" ] && _err "Missing CZ_Zones" && return 1
  CZ_API_BASE="${CZ_API_BASE:-https://api.czechia.com}"
  _saveaccountconf_mutable CZ_AuthorizationToken "$CZ_AuthorizationToken"
  _saveaccountconf_mutable CZ_Zones "$CZ_Zones"
  return 0
}

_czechia_pick_zone() {
  _fd=$(printf "%s" "$1" | _lower_case | sed 's/\.$//')
  _best_zone=""
  _zones_space=$(printf "%s" "$CZ_Zones" | sed 's/,/ /g')
  for _z in $_zones_space; do
    _clean_z=$(printf "%s" "$_z" | _lower_case | sed 's/ //g; s/\.$//')
    [ -z "$_clean_z" ] && continue
    case "$_fd" in
    "$_clean_z" | *".$_clean_z")
      if [ ${#_clean_z} -gt ${#_best_zone} ]; then _best_zone="$_clean_z"; fi
      ;;
    esac
  done
  printf "%s" "$_best_zone"
}
