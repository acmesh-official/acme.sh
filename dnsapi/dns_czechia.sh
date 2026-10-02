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
  fulldomain="$1"
  txtvalue="$2"

  _debug "dns_czechia_add fulldomain='$fulldomain'"

  if [ -z "$fulldomain" ] || [ -z "$txtvalue" ]; then
    _err "dns_czechia_add: missing fulldomain or txtvalue"
    return 1
  fi

  _czechia_load_conf || return 1

  _current_zone=$(_czechia_pick_zone "$fulldomain")
  if [ -z "$_current_zone" ]; then
    _err "No matching zone found for $fulldomain. Please check CZ_Zones."
    return 1
  fi

  _cz=$(printf "%s" "$_current_zone" | _lower_case | sed 's/[[:space:]]//g; s/\.$//')
  _tk=$(printf "%s" "$CZ_AuthorizationToken" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

  if [ -z "$_cz" ] || [ -z "$_tk" ]; then
    _err "Missing zone or CZ_AuthorizationToken."
    return 1
  fi

  _url="$CZ_API_BASE/api/DNS/$_cz/TXT"
  _fd=$(printf "%s" "$fulldomain" | _lower_case | sed 's/\.$//')

  if [ "$_fd" = "$_cz" ]; then
    _h="@"
  else
    # Remove the literal ".<zone>" suffix from _fd, if present
    _h=${_fd%."$_cz"}
    [ "$_h" = "$_fd" ] && _h="@"
  fi
  [ -z "$_h" ] && _h="@"

  _info "Adding TXT record for $_h in zone $_cz"

  _h_esc=$(printf "%s" "$_h" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _txt_esc=$(printf "%s" "$txtvalue" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _body="{\"hostName\":\"$_h_esc\",\"text\":\"$_txt_esc\",\"ttl\":300,\"publishZone\":1}"

  _debug "URL: $_url"
  _debug "Body: $_body"

  export _H1="Content-Type: application/json"
  export _H2="AuthorizationToken: $_tk"

  _res="$(_post "$_body" "$_url" "" "POST")"
  _post_exit="$?"
  _debug2 "Response: $_res"

  if [ "$_post_exit" -ne 0 ]; then
    _err "API request failed. exit code $_post_exit"
    return 1
  fi

  if _contains "$_res" "already exists"; then
    _info "Record already exists, skipping."
    return 0
  fi

  _nres="$(_normalizeJson "$_res")"
  if [ "$?" -ne 0 ] || [ -z "$_nres" ]; then
    _nres="$_res"
  fi

  if _contains "$_nres" "\"status\":4" || _contains "$_nres" "\"status\":5" || _contains "$_nres" "\"errors\""; then
    _err "API error: $_res"
    return 1
  fi

  return 0
}

dns_czechia_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _debug "dns_czechia_rm fulldomain='$fulldomain'"

  if [ -z "$fulldomain" ] || [ -z "$txtvalue" ]; then
    _err "dns_czechia_rm: missing fulldomain or txtvalue"
    return 1
  fi

  _czechia_load_conf || return 1

  _current_zone=$(_czechia_pick_zone "$fulldomain")
  if [ -z "$_current_zone" ]; then
    _err "No matching zone found for $fulldomain. Please check CZ_Zones configuration."
    return 1
  fi

  _cz=$(printf "%s" "$_current_zone" | _lower_case | sed 's/[[:space:]]//g; s/\.$//')
  _tk=$(printf "%s" "$CZ_AuthorizationToken" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

  if [ -z "$_cz" ] || [ -z "$_tk" ]; then
    _err "Missing zone or CZ_AuthorizationToken."
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

  _h_esc=$(printf "%s" "$_h" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _txt_esc=$(printf "%s" "$txtvalue" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _body="{\"hostName\":\"$_h_esc\",\"text\":\"$_txt_esc\",\"ttl\":300,\"publishZone\":1}"

  _debug "URL: $_url"
  _debug "Body: $_body"

  export _H1="Content-Type: application/json"
  export _H2="AuthorizationToken: $_tk"

  _res="$(_post "$_body" "$_url" "" "DELETE")"
  _post_exit="$?"
  _debug2 "Response: $_res"

  if [ "$_post_exit" -ne 0 ]; then
    _err "CZECHIA DNS API DELETE request failed for $_fd: exit code $_post_exit, response: $_res"
    return 1
  fi

  _res_normalized=$(printf '%s' "$_res" | _normalizeJson)

  if _contains "$_res_normalized" '"isError":true'; then
    _err "CZECHIA DNS API reported an error while deleting TXT for $_fd: $_res"
    return 1
  fi

  return 0
}

_czechia_load_conf() {
  CZ_AuthorizationToken="${CZ_AuthorizationToken:-$(_readaccountconf_mutable CZ_AuthorizationToken)}"
  if [ -z "$CZ_AuthorizationToken" ]; then
    _err "Missing CZ_AuthorizationToken"
    return 1
  fi

  CZ_Zones="${CZ_Zones:-$(_readaccountconf_mutable CZ_Zones)}"
  if [ -z "$CZ_Zones" ]; then
    _err "Missing CZ_Zones"
    return 1
  fi

  CZ_API_BASE="${CZ_API_BASE:-$(_readaccountconf_mutable CZ_API_BASE)}"
  [ -z "$CZ_API_BASE" ] && CZ_API_BASE="https://api.czechia.com"

  _saveaccountconf_mutable CZ_AuthorizationToken "$CZ_AuthorizationToken"
  _saveaccountconf_mutable CZ_Zones "$CZ_Zones"
  _saveaccountconf_mutable CZ_API_BASE "$CZ_API_BASE"

  return 0
}

_czechia_pick_zone() {
  _fd=$(printf "%s" "$1" | _lower_case | sed 's/\.$//')
  _best_zone=""

  _zones_space=$(printf "%s" "$CZ_Zones" | sed 's/,/ /g')
  for _z in $_zones_space; do
    _clean_z=$(printf "%s" "$_z" | _lower_case | sed 's/[[:space:]]//g; s/\.$//')
    [ -z "$_clean_z" ] && continue

    case "$_fd" in
    "$_clean_z" | *."$_clean_z")
      if [ ${#_clean_z} -gt ${#_best_zone} ]; then
        _best_zone="$_clean_z"
      fi
      ;;
    esac
  done

  printf "%s" "$_best_zone"
}
