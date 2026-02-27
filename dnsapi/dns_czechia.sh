#!/usr/bin/env sh

# dns_czechia.sh - CZECHIA.COM/ZONER DNS API for acme.sh (DNS-01)
#
# Documentation: https://api.czechia.com/swagger/index.html
#
# Required environment variables:
#   CZ_AuthorizationToken   Your API token from CZECHIA.COM/Zoner administration.
#   CZ_Zones                Managed zones separated by comma or space (e.g. "example.com").
#
# Optional environment variables:
#   CZ_API_BASE             Defaults to https://api.czechia.com

dns_czechia_add() {
  fulldomain="$1"
  txtvalue="$2"
  _czechia_load_conf || return 1
  _current_zone=$(_czechia_pick_zone "$fulldomain")
  if [ -z "$_current_zone" ]; then
    _err "No matching zone found for $fulldomain. Please check CZ_Zones."
    return 1
  fi

  # Totální očista zóny (povolena jen malá písmena, čísla, tečky a pomlčky)
  _current_zone=$(printf "%s" "$_current_zone" | _lower_case | sed 's/[^a-z0-9.-]//g; s/\.$//')
  _url="$CZ_API_BASE/api/DNS/$_current_zone/TXT"

  _fd=$(echo "$fulldomain" | _lower_case | sed 's/\.$//')
  _cz=$(echo "$_current_zone" | _lower_case | sed 's/\.$//')

  _h=$(echo "$_fd" | sed "s/\.$_cz$//; s/^$_cz$//")
  [ -z "$_h" ] && _h="@"

  _info "Adding TXT record for $_h in zone $_current_zone"
  _body="{\"hostName\":\"$_h\",\"text\":\"$txtvalue\",\"ttl\":3600,\"publishZone\":1}"

  export _H1="Content-Type: application/json"
  export _H2="authorizationToken: $CZ_AuthorizationToken"

  _res=$(_post "$_body" "$_url" "" "POST")
  if _contains "$_res" "errors" || _contains "$_res" "400"; then
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

  # Totální očista zóny
  _current_zone=$(printf "%s" "$_current_zone" | _lower_case | sed 's/[^a-z0-9.-]//g; s/\.$//')
  _url="$CZ_API_BASE/api/DNS/$_current_zone/TXT"

  _fd=$(echo "$fulldomain" | _lower_case | sed 's/\.$//')
  _cz=$(echo "$_current_zone" | _lower_case | sed 's/\.$//')

  _h=$(echo "$_fd" | sed "s/\.$_cz$//; s/^$_cz$//")
  [ -z "$_h" ] && _h="@"

  _info "Removing TXT record $_h"
  _body="{\"hostName\":\"$_h\",\"text\":\"$txtvalue\",\"publishZone\":1}"

  export _H1="Content-Type: application/json"
  export _H2="authorizationToken: $CZ_AuthorizationToken"
  _res=$(_post "$_body" "$_url" "" "DELETE")
  return 0
}

_czechia_load_conf() {
  CZ_AuthorizationToken="${CZ_AuthorizationToken:-$(_getaccountconf CZ_AuthorizationToken)}"
  [ -z "$CZ_AuthorizationToken" ] && _err "Missing CZ_AuthorizationToken" && return 1
  CZ_Zones="${CZ_Zones:-$(_getaccountconf CZ_Zones)}"
  [ -z "$CZ_Zones" ] && _err "Missing CZ_Zones" && return 1
  CZ_API_BASE="${CZ_API_BASE:-https://api.czechia.com}"
  _saveaccountconf CZ_AuthorizationToken "$CZ_AuthorizationToken"
  _saveaccountconf CZ_Zones "$CZ_Zones"
  return 0
}

_czechia_pick_zone() {
  _fd_input="$1"
  _fd=$(echo "$_fd_input" | _lower_case | sed 's/\.$//')
  _best_zone=""
  _zones_space=$(printf "%s" "$CZ_Zones" | sed 's/,/ /g')

  for _z in $_zones_space; do
    _clean_z=$(echo "$_z" | _lower_case | sed 's/ //g; s/\.$//')
    [ -z "$_clean_z" ] && continue
    case "$_fd" in
    "$_clean_z" | *".$_clean_z")
      if [ ${#_clean_z} -gt ${#_best_zone} ]; then
        _best_zone="$_clean_z"
      fi
      ;;
    esac
  done
  [ -n "$_best_zone" ] && printf "%s" "$_best_zone"
}
