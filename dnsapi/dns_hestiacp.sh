#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_hestiacp_info='HestiaCP Server API
Site: hestiacp.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_hestiacp
Options:
 HESTIA_HOST Panel URL. E.g. "https://panel.example.com:8083"
 HESTIA_ACCESS API access key
 HESTIA_SECRET API secret key
 HESTIA_USER Username owning the DNS zones. Default "admin". Optional.
Issues: github.com/acmesh-official/acme.sh/issues/6251
Author: Radu Malica <radu.malica@gmail.com>
'

########  Public functions #####################

# Usage: dns_hestiacp_add fulldomain txtvalue
dns_hestiacp_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _hestia_init; then
    return 1
  fi

  _debug "Detecting the root zone for $fulldomain"
  if ! _hestia_get_root "$fulldomain"; then
    _err "Cannot find a DNS zone for $fulldomain under user $HESTIA_USER"
    return 1
  fi
  _debug _hestia_domain "$_hestia_domain"
  _debug _hestia_sub "$_hestia_sub"

  # _hestia_get_root left the zone record listing in _hestia_response
  if _hestia_find_records "$_hestia_sub" "TXT" | grep -F -- "$txtvalue" >/dev/null; then
    _info "The TXT record already exists, skipping"
    return 0
  fi

  _info "Adding TXT record for $fulldomain"
  if ! _hestia_rest "v-add-dns-record" "$HESTIA_USER" "$_hestia_domain" "$_hestia_sub" "TXT" "$txtvalue" "" "" "yes" "600"; then
    _err "Error adding TXT record: $_hestia_response"
    return 1
  fi
  _info "TXT record added successfully"
  return 0
}

# Usage: dns_hestiacp_rm fulldomain txtvalue
dns_hestiacp_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _hestia_init; then
    return 1
  fi

  _debug "Detecting the root zone for $fulldomain"
  if ! _hestia_get_root "$fulldomain"; then
    _err "Cannot find a DNS zone for $fulldomain under user $HESTIA_USER"
    return 1
  fi
  _debug _hestia_domain "$_hestia_domain"
  _debug _hestia_sub "$_hestia_sub"

  _hestia_removed=0
  _hestia_failed=0
  while IFS='|' read -r _hestia_id _hestia_value || [ -n "$_hestia_id" ]; do
    if [ -z "$_hestia_id" ]; then
      continue
    fi
    if ! _contains "$_hestia_value" "$txtvalue"; then
      continue
    fi
    _info "Deleting TXT record $_hestia_id"
    if ! _hestia_rest "v-delete-dns-record" "$HESTIA_USER" "$_hestia_domain" "$_hestia_id" "yes"; then
      _err "Error deleting TXT record $_hestia_id: $_hestia_response"
      _hestia_failed=$(_math "$_hestia_failed" + 1)
      continue
    fi
    _hestia_removed=$(_math "$_hestia_removed" + 1)
  done <<EOF
$(_hestia_find_records "$_hestia_sub" "TXT")
EOF

  if [ "$_hestia_removed" = "0" ] && [ "$_hestia_failed" = "0" ]; then
    _info "No matching TXT record found to remove"
  else
    _info "Removed $_hestia_removed TXT record(s)"
  fi

  if [ "$_hestia_failed" != "0" ]; then
    return 1
  fi
  return 0
}

####################  Private functions below ##################################

_hestia_init() {
  HESTIA_HOST="${HESTIA_HOST:-$(_readaccountconf_mutable HESTIA_HOST)}"
  HESTIA_ACCESS="${HESTIA_ACCESS:-$(_readaccountconf_mutable HESTIA_ACCESS)}"
  HESTIA_SECRET="${HESTIA_SECRET:-$(_readaccountconf_mutable HESTIA_SECRET)}"
  HESTIA_USER="${HESTIA_USER:-$(_readaccountconf_mutable HESTIA_USER)}"

  if [ -z "$HESTIA_HOST" ] || [ -z "$HESTIA_ACCESS" ] || [ -z "$HESTIA_SECRET" ]; then
    HESTIA_HOST=""
    HESTIA_ACCESS=""
    HESTIA_SECRET=""
    _err "You must export HESTIA_HOST, HESTIA_ACCESS and HESTIA_SECRET first"
    return 1
  fi

  HESTIA_HOST="${HESTIA_HOST%/}"
  if ! echo "$HESTIA_HOST" | grep -qE '^https?://[^/]+$'; then
    _err "HESTIA_HOST must be a valid URL (e.g. https://panel.example.com:8083)"
    return 1
  fi

  if [ -z "$HESTIA_USER" ]; then
    HESTIA_USER="admin"
  fi

  _saveaccountconf_mutable HESTIA_HOST "$HESTIA_HOST"
  _saveaccountconf_mutable HESTIA_ACCESS "$HESTIA_ACCESS"
  _saveaccountconf_mutable HESTIA_SECRET "$HESTIA_SECRET"
  _saveaccountconf_mutable HESTIA_USER "$HESTIA_USER"
  return 0
}

# Walk up the domain labels until the API returns a DNS zone.
# Sets _hestia_domain to the zone and _hestia_sub to the record name
# relative to the zone. The zone record listing stays in _hestia_response.
_hestia_get_root() {
  _hestia_fqdn="${1%.}"
  _hestia_i=1
  while true; do
    _hestia_h=$(printf "%s" "$_hestia_fqdn" | cut -d . -f "$_hestia_i"-100)
    _debug2 _hestia_h "$_hestia_h"
    if [ -z "$_hestia_h" ]; then
      return 1
    fi
    if _hestia_rest "v-list-dns-records" "$HESTIA_USER" "$_hestia_h" "json"; then
      _hestia_domain="$_hestia_h"
      if [ "$_hestia_h" = "$_hestia_fqdn" ]; then
        _hestia_sub="@"
      else
        _hestia_sub=$(printf "%s" "$_hestia_fqdn" | cut -d . -f 1-"$(_math "$_hestia_i" - 1)")
      fi
      return 0
    fi
    _hestia_i=$(_math "$_hestia_i" + 1)
  done
}

# Call the HestiaCP API. Args: cmd [arg1 arg2 ...]
# The response body is stored in _hestia_response.
_hestia_rest() {
  _hestia_cmd=$1
  shift

  _hestia_data="{\"access_key\":\"$HESTIA_ACCESS\",\"secret_key\":\"$HESTIA_SECRET\",\"cmd\":\"$_hestia_cmd\""
  _hestia_argn=1
  for _hestia_arg in "$@"; do
    _hestia_data="$_hestia_data,\"arg$_hestia_argn\":\"$_hestia_arg\""
    _hestia_argn=$(_math "$_hestia_argn" + 1)
  done
  _hestia_data="$_hestia_data}"

  _debug2 "Calling $_hestia_cmd"
  _hestia_response=$(_post "$_hestia_data" "$HESTIA_HOST/api/" "" "POST" "application/json")
  _hestia_ret=$?
  _debug2 _hestia_response "$_hestia_response"
  if [ "$_hestia_ret" != "0" ]; then
    _err "Error connecting to the HestiaCP API"
    return 1
  fi
  if _contains "$_hestia_response" "Error:"; then
    return 1
  fi
  return 0
}

# Extract records matching name and type from the v-list-dns-records
# response in _hestia_response. Prints one "id|value" line per match.
_hestia_find_records() {
  _hestia_fname=$1
  _hestia_ftype=$2

  echo "$_hestia_response" | tr -d '\n' | sed 's/},/}\
/g' | grep -F -- "\"RECORD\": \"$_hestia_fname\"" | grep -F -- "\"TYPE\": \"$_hestia_ftype\"" | while read -r _hestia_line; do
    _hestia_id=$(echo "$_hestia_line" | _egrep_o '"ID": "[^"]*' | cut -d '"' -f 4)
    _hestia_value=$(echo "$_hestia_line" | _egrep_o '"VALUE": "[^"]*' | cut -d '"' -f 4)
    if [ -n "$_hestia_id" ]; then
      echo "$_hestia_id|$_hestia_value"
    fi
  done
}
