#!/usr/bin/env sh

# dns_czechia.sh - Czechia/ZONER DNS API for acme.sh (DNS-01)
#
# Documentation: https://api.czechia.com/swagger/index.html
#
# Required environment variables:
#   CZ_AuthorizationToken   Your API token from Czechia/Zoner administration.
#   CZ_Zones                Managed zones separated by comma or space (e.g. "example.com,example.net").
#                           The plugin picks the best matching zone for each domain.
#
# Optional environment variables:
#   CZ_API_BASE             Defaults to https://api.czechia.com
#   CZ_CURL_TIMEOUT         Defaults to 30

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
  
  # Calculate hostname: remove zone from fulldomain
  _h=$(printf "%s" "$fulldomain" | sed "s/\.$_current_zone//; s/$_current_zone//")
  
  # Apex domain handling
  if [ -z "$_h" ]; then
    _h="@"
  fi

  # Build JSON body (POSIX compatible)
  _q='"'
  _body="{$_q"hostName"$_q:$_q$_h$_q,$_q"text"$_q:$_q$txtvalue$_q,$_q"ttl"$_q:3600,$_q"publishZone"$_q:1}"

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
  _h=$(printf "%s" "$fulldomain" | sed "s/\.$_current_zone//; s/$_current_zone//")
  [ -z "$_h" ] && _h="@"

  _q='"'
  _body="{$_q"hostName"$_q:$_q$_h$_q,$_q"text"$_q:$_q$txtvalue$_q,$_q"publishZone"$_q:1}"

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
  if [ -z "$CZ_AuthorizationToken" ]; then
    CZ_AuthorizationToken="$(_getaccountconf CZ_AuthorizationToken)"
  fi
  if [ -z "$CZ_AuthorizationToken" ]; then
    _err "You didn't specify Czechia Authorization Token (CZ_AuthorizationToken)."
    return 1
  fi

  if [ -z "$CZ_Zones" ]; then
    CZ_Zones="$(_getaccountconf CZ_Zones)"
  fi
  if [ -z "$CZ_Zones" ]; then
    _err "You didn't specify Czechia Zones (CZ_Zones)."
    return 1
  fi

  # Defaults
  if [ -z "$CZ_API_BASE" ]; then
    CZ_API_BASE="https://api.czechia.com"
  fi
  
  # Save to account.conf for renewals
  _saveaccountconf CZ_AuthorizationToken "$CZ_AuthorizationToken"
  _saveaccountconf CZ_Zones "$CZ_Zones"
  
  return 0
}

_czechia_pick_zone() {
  _fulldomain="$1"
  # Lowercase and remove trailing dot
  _fd=$(printf "%s" "$_fulldomain" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//')
  
  _best_zone=""
  
  # Split zones by comma or space
  _zones_space=$(printf "%s" "$CZ_Zones" | tr ',' ' ')

  for _z in $_zones_space; do
    _clean_z=$(printf "%s" "$_z" | tr -d ' ' | tr '[:upper:]' '[:lower:]' | sed 's/\.$//')
    [ -z "$_clean_z" ] && continue
    
    case "$_fd" in
      "$_clean_z"|*".$_clean_z")
        # Find the longest matching zone suffix
        _new_len=$(printf "%s" "$_clean_z" | wc -c)
        _old_len=$(printf "%s" "$_best_zone" | wc -c)
        if [ "$_new_len" -gt "$_old_len" ]; then
          _best_zone="$_clean_z"
        fi
        ;;
    esac
  done

  if [ -z "$_best_zone" ]; then
    return 1
  fi

  printf "%s" "$_best_zone"
}
