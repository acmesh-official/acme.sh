#!/usr/bin/env sh

# dns_czechia.sh - Czechia/ZONER DNS API for acme.sh (DNS-01)
#
# Documentation: https://api.czechia.com/swagger/index.html
#
# Required environment variables:
#   CZ_AuthorizationToken   Your API token from Czechia/Zoner administration.
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

  _url="$CZ_API_BASE/api/DNS/$_current_zone/TXT"

  # Normalize using acme.sh internal function for consistency
  _fd=$(_lower_case "$fulldomain" | sed 's/\.$//')
  _cz=$(_lower_case "$_current_zone")

  # Calculate hostname
  _h=$(printf "%s" "$_fd" | sed "s/\.$_cz//; s/$_cz//")
  [ -z "$_h" ] && _h="@"

  _body="{\"hostName\":\"$_h\",\"text\":\"$txtvalue\",\"ttl\":3600,\"publishZone\":1}"

  _info "Adding TXT record for $fulldomain"

  export _H1="Content-Type: application/json"
  export _H2="authorizationToken: $CZ_AuthorizationToken"

  _res=$(_post "$_body" "$_url" "" "POST")
  _debug "API Response: $_res"

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

  _url="$CZ_API_BASE/api/DNS/$_current_zone/TXT"

  _fd=$(_lower_case "$fulldomain" | sed 's/\.$//')
  _cz=$(_lower_case "$_current_zone")
  _h=$(printf "%s" "$_fd" | sed "s/\.$_cz//; s/$_cz//")
  [ -z "$_h" ] && _h="@"

  _body="{\"hostName\":\"$_h\",\"text\":\"$txtvalue\",\"publishZone\":1}"

  _info "Removing TXT record for $fulldomain"

  export _H1="Content-Type: application/json"
  export _H2="authorizationToken: $CZ_AuthorizationToken"

  _res=$(_post "$_body" "$_url" "" "DELETE")
  _debug "API Response: $_res"

  return 0
}

########################################################################
# Private functions
########################################################################

_czechia_load_conf() {
  CZ_AuthorizationToken="${CZ_AuthorizationToken:-$(_getaccountconf CZ_AuthorizationToken)}"
  if [ -z "$CZ_AuthorizationToken" ]; then
    _err "You didn't specify CZ_AuthorizationToken."
    return 1
  fi

  CZ_Zones="${CZ_Zones:-$(_getaccountconf CZ_Zones)}"
  if [ -z "$CZ_Zones" ]; then
    _err "You didn't specify CZ_Zones."
    return 1
  fi

  CZ_API_BASE="${CZ_API_BASE:-https://api.czechia.com}"

  _saveaccountconf CZ_AuthorizationToken "$CZ_AuthorizationToken"
  _saveaccountconf CZ_Zones "$CZ_Zones"
  return 0
}

_czechia_pick_zone() {
  _fulldomain="$1"
  _fd=$(_lower_case "$_fulldomain" | sed 's/\.$//')
  _best_zone=""

  # Bezpečné rozdělení zón bez tr
  _zones_space=$(printf "%s" "$CZ_Zones" | sed 's/,/ /g')

  for _z in $_zones_space; do
    _clean_z=$(_lower_case "$_z" | sed 's/ //g; s/\.$//')
    [ -z "$_clean_z" ] && continue

    case "$_fd" in
    "$_clean_z" | *".$_clean_z")
      # Místo wc -c použijeme délku řetězce přímo v shellu (nejstabilnější v Dockeru)
      _new_len=${#_clean_z}
      _old_len=${#_best_zone}
      if [ "$_new_len" -gt "$_old_len" ]; then
        _best_zone="$_clean_z"
      fi
      ;;
    esac
  done

  if [ -n "$_best_zone" ]; then
    printf "%s" "$_best_zone"
  fi
}

  [ "$_best_zone" ] && printf "%s" "$_best_zone"
}
