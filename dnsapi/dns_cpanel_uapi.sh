#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_cpanel_uapi_info='cPanel UAPI
 Manage DNS via cPanel UAPI. Works with API tokens and Two-Factor Authentication.
Site: cpanel.net
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_cpanel_uapi
Options:
 cPanel_Username Username
 cPanel_Apitoken API Token
 cPanel_Hostname Server URL. E.g. "https://hostname:port"
 cPanel_TTL optional TXT record TTL in seconds. Default: 120
Issues: github.com/acmesh-official/acme.sh/issues/6877
Author: Adam Bodnar
'

########  Public functions #####################

# Used to add txt record
dns_cpanel_uapi_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Adding TXT record via cPanel UAPI"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _cpanel_uapi_get_root; then
    _err "No matching root domain for $fulldomain found"
    return 1
  fi

  # Build the record name relative to the zone
  _escaped_domain=$(echo "$_domain" | sed 's/\./\\./g')
  _record_name=$(echo "$fulldomain" | sed "s/\.${_escaped_domain}$//")
  _debug "Record name: $_record_name in zone $_domain"

  # Get the current SOA serial (required by mass_edit_zone)
  if ! _cpanel_uapi_get_serial "$_domain"; then
    _err "Failed to get zone serial for $_domain"
    return 1
  fi
  _debug "Zone serial: $_serial"

  # Use configurable TTL, default 120 seconds
  _ttl="${cPanel_TTL:-$(_readaccountconf_mutable cPanel_TTL)}"
  case "$_ttl" in
  "")
    _ttl=120
    ;;
  *[!0-9]*)
    _debug "Invalid cPanel_TTL provided, falling back to default 120"
    _ttl=120
    ;;
  esac

  # Build JSON and URL-encode it for the add parameter
  _add_json=$(printf '{"dname":"%s","ttl":%s,"record_type":"TXT","data":["%s"]}' "$_record_name" "$_ttl" "$txtvalue")
  _debug "add_json: $_add_json"
  _add_json_encoded=$(printf '%s' "$_add_json" | _url_encode)
  _debug "add_json (encoded): $_add_json_encoded"

  if ! _cpanel_uapi_request "execute/DNS/mass_edit_zone?zone=${_domain}&serial=${_serial}&add=${_add_json_encoded}"; then
    _err "Request to add TXT record failed for zone $_domain"
    return 1
  fi
  _debug "_result: $_result"

  if _contains "$_result" '"status":1'; then
    _info "TXT record added successfully"
    return 0
  fi
  _err "Failed to add TXT record."
  _err "Response: $_result"
  return 1
}

# Used to remove the txt record after validation
dns_cpanel_uapi_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Removing TXT record via cPanel UAPI"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _cpanel_uapi_get_root; then
    _err "No matching root domain for $fulldomain found"
    return 1
  fi

  if ! _cpanel_uapi_findentry; then
    _info "Entry doesn't exist, nothing to delete"
    return 0
  fi

  _debug "Deleting record with line_index=$_line_index"
  if ! _cpanel_uapi_get_serial "$_domain"; then
    _err "Failed to get zone serial for $_domain"
    return 1
  fi
  if ! _cpanel_uapi_request "execute/DNS/mass_edit_zone?zone=${_domain}&serial=${_serial}&remove=${_line_index}"; then
    _err "Request to remove TXT record failed for zone $_domain"
    return 1
  fi
  _debug "_result: $_result"

  if _contains "$_result" '"status":1'; then
    _info "TXT record removed successfully"
    return 0
  fi
  _err "Failed to remove TXT record."
  _err "Response: $_result"
  return 1
}

####################  Private functions below ##################################

_cpanel_uapi_checkcredentials() {
  cPanel_Username="${cPanel_Username:-$(_readaccountconf_mutable cPanel_Username)}"
  cPanel_Apitoken="${cPanel_Apitoken:-$(_readaccountconf_mutable cPanel_Apitoken)}"
  cPanel_Hostname="${cPanel_Hostname:-$(_readaccountconf_mutable cPanel_Hostname)}"

  if [ -z "$cPanel_Username" ] || [ -z "$cPanel_Apitoken" ] || [ -z "$cPanel_Hostname" ]; then
    cPanel_Username=""
    cPanel_Apitoken=""
    cPanel_Hostname=""
    _err "You haven't specified cPanel_Username, cPanel_Apitoken, and cPanel_Hostname."
    return 1
  fi

  # Remove trailing slash from hostname if present
  cPanel_Hostname=$(echo "$cPanel_Hostname" | sed 's|/$||')

  _saveaccountconf_mutable cPanel_Username "$cPanel_Username"
  _saveaccountconf_mutable cPanel_Apitoken "$cPanel_Apitoken"
  _saveaccountconf_mutable cPanel_Hostname "$cPanel_Hostname"

  if [ -n "$cPanel_TTL" ]; then
    case "$cPanel_TTL" in
    *[!0-9]*)
      _info "Ignoring invalid cPanel_TTL: $cPanel_TTL"
      cPanel_TTL=""
      ;;
    *)
      _saveaccountconf_mutable cPanel_TTL "$cPanel_TTL"
      ;;
    esac
  fi
  return 0
}

_cpanel_uapi_request() {
  export _H1="Authorization: cpanel $cPanel_Username:$cPanel_Apitoken"
  _result=$(_get "$cPanel_Hostname/$1")
  return $?
}

_cpanel_uapi_get_root() {
  if ! _cpanel_uapi_checkcredentials; then return 1; fi

  if ! _cpanel_uapi_request "execute/DomainInfo/list_domains"; then
    _err "Request to cPanel API failed while listing domains"
    return 1
  fi
  _debug "DomainInfo response length: ${#_result}"

  if ! _contains "$_result" '"status":1'; then
    _err "cPanel UAPI request failed. Is the API token correct?"
    _debug "Response: $_result"
    return 1
  fi

  # Extract main_domain
  _main_domain=$(echo "$_result" | _egrep_o '"main_domain":"[^"]*"' | _head_n 1 | sed 's/.*"main_domain":"//;s/"//')
  _debug "main_domain: $_main_domain"

  # Extract addon_domains (array of strings)
  _addon_domains=$(echo "$_result" | _egrep_o '"addon_domains":\[[^]]*\]' | sed 's/.*"addon_domains":\[//;s/\]$//' | _egrep_o '"[a-zA-Z0-9._-]+"' | sed 's/"//g')
  _debug "addon_domains: $_addon_domains"

  # Build list of all domains to check
  _all_domains="$_main_domain $_addon_domains"
  _debug "All domains: $_all_domains"

  # Find the matching root domain (prefer longest match)
  _best_match=""
  _best_len=0
  for _check_domain in $_all_domains; do
    if [ -z "$_check_domain" ]; then continue; fi
    if _endswith "$fulldomain" "$_check_domain"; then
      _len=${#_check_domain}
      if [ "$_len" -gt "$_best_len" ]; then
        _best_match="$_check_domain"
        _best_len="$_len"
      fi
    fi
  done

  if [ -n "$_best_match" ]; then
    _domain="$_best_match"
    _debug "Root domain: $_domain"
    return 0
  fi
  return 1
}

_cpanel_uapi_get_serial() {
  _zone="$1"
  if ! _cpanel_uapi_request "execute/DNS/parse_zone?zone=${_zone}"; then
    _err "Request to parse zone failed for $_zone"
    return 1
  fi

  # Split JSON records onto separate lines using a POSIX-portable sed literal newline
  # (\\n in sed replacement is a GNU/BusyBox extension; a backslash-newline works everywhere)
  _soa_line=$(echo "$_result" | sed 's/},{/},\
{/g' | grep '"record_type":"SOA"' | _head_n 1)
  _debug "SOA line: $_soa_line"

  if [ -z "$_soa_line" ]; then
    _err "SOA record not found for zone $_zone"
    _debug "parse_zone response: $_result"
    return 1
  fi

  # Extract the third element from data_b64 array (serial is index 2, 0-based)
  # data_b64 format: ["ns","admin","SERIAL","refresh","retry","expire","minimum"]
  _serial_b64=$(echo "$_soa_line" | _egrep_o '"data_b64":\[[^]]*\]' | sed 's/"data_b64":\[//;s/\]//' | sed 's/"//g' | cut -d',' -f3)
  _debug "serial_b64: $_serial_b64"

  if [ -z "$_serial_b64" ]; then
    _err "Could not extract serial from SOA record"
    return 1
  fi

  _serial=$(printf '%s' "$_serial_b64" | _dbase64)
  _debug "Decoded serial: $_serial"

  if [ -z "$_serial" ]; then
    _err "Failed to decode serial"
    return 1
  fi
  return 0
}

_cpanel_uapi_findentry() {
  _debug "Finding TXT entry for $fulldomain with value $txtvalue"

  if ! _cpanel_uapi_request "execute/DNS/parse_zone?zone=${_domain}"; then
    _err "Request to parse zone failed for $_domain"
    return 1
  fi
  _debug "parse_zone result length: ${#_result}"

  # Base64-encode the txtvalue to match against data_b64 in the response
  _b64_txtvalue=$(printf '%s' "$txtvalue" | _base64)
  _debug "b64_txtvalue: $_b64_txtvalue"

  # Split records onto separate lines, find matching TXT record by base64 value
  _line_index=$(echo "$_result" | sed 's/},{/},\
{/g' | grep '"record_type":"TXT"' | grep -F "$_b64_txtvalue" | _egrep_o '"line_index":[0-9]+' | _head_n 1 | cut -d: -f2)
  _debug "line_index: $_line_index"

  if [ -n "$_line_index" ]; then
    _debug "Entry found with line_index=$_line_index"
    return 0
  fi
  return 1
}
