#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_mizban_info='MizbanCloud
Site: MizbanCloud.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_mizban
Options:
 Mizban_Token API Token. Create it in the MizbanCloud panel.
Author: hosni
'

# https://auth.mizbancloud.com/api/v1/cdn/ng
# Apex names are stored as the zone name. Every other name is relative to the
# zone. The same TXT value again returns HTTP 422. A different value at the
# same name is kept, so a wildcard certificate can have two challenges.

MIZBAN_API="https://auth.mizbancloud.com/api/v1/cdn/ng"

########  Public functions #####################

# Usage: dns_mizban_add _acme-challenge.www.example.com "TXT value"
dns_mizban_add() {
  fulldomain="$(_idn "$1")"
  txtvalue=$2

  if ! _mizban_init; then
    return 1
  fi
  _saveaccountconf_mutable Mizban_Token "$Mizban_Token"

  _debug "First detect the root zone"
  if ! _mizban_find_zone "$fulldomain"; then
    _err "No MizbanCloud domain matches $fulldomain."
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"
  _debug _domain_id "$_domain_id"

  if ! _mizban_find_records; then
    return 1
  fi
  if [ "$_mizban_record_ids" ]; then
    _info "The TXT record already exists."
    return 0
  fi

  _info "Adding TXT record."
  _mizban_body="{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"ttl\":120,\"content\":\"$txtvalue\"}"
  if ! _mizban_rest POST "domains/$_domain_id/dns" "$_mizban_body"; then
    case "$_mizban_message" in
    *[Dd]uplicat*)
      _info "The TXT record already exists."
      return 0
      ;;
    esac
    _mizban_api_error "adding the TXT record"
    return 1
  fi
  _info "Added, OK"
  return 0
}

# Usage: dns_mizban_rm _acme-challenge.www.example.com "TXT value"
dns_mizban_rm() {
  fulldomain="$(_idn "$1")"
  txtvalue=$2

  if ! _mizban_init; then
    return 1
  fi
  if ! _mizban_find_zone "$fulldomain"; then
    _err "No MizbanCloud domain matches $fulldomain."
    return 1
  fi
  if ! _mizban_find_records; then
    return 1
  fi
  if [ -z "$_mizban_record_ids" ]; then
    _info "The TXT record is already absent."
    return 0
  fi

  _info "Removing TXT record."
  for _mizban_record_id in $_mizban_record_ids; do
    if ! _mizban_rest DELETE "domains/$_domain_id/dns/$_mizban_record_id"; then
      _mizban_api_error "removing the TXT record"
      return 1
    fi
  done
  _info "Removed, OK"
  return 0
}

####################  Private functions below ##################################

_mizban_init() {
  Mizban_Token="${Mizban_Token:-$(_readaccountconf_mutable Mizban_Token)}"
  Mizban_Token=${Mizban_Token#\"}
  Mizban_Token=${Mizban_Token%\"}
  if [ -z "$Mizban_Token" ]; then
    _err "Mizban_Token is not set."
    _err "Create an API token in the MizbanCloud panel and export Mizban_Token."
    return 1
  fi
}

# _domain, _domain_id, _sub_domain ("@" at the zone apex).
_mizban_find_zone() {
  domain=$(printf "%s" "$1" | _lower_case)
  domain=${domain%.}

  if ! _mizban_rest GET "domains"; then
    _mizban_api_error "listing domains"
    return 1
  fi
  _mizban_zones=$(_mizban_pairs)
  if [ -z "$_mizban_zones" ]; then
    _err "This MizbanCloud account has no domains."
    return 1
  fi

  h=$domain
  while true; do
    _domain_id=""
    while IFS= read -r _mizban_line; do
      [ -z "$_mizban_line" ] && continue
      if [ "${_mizban_line#* }" = "$h" ]; then
        _domain_id="${_mizban_line%% *}"
        break
      fi
    done <<EOF
$_mizban_zones
EOF
    if [ "$_domain_id" ]; then
      _domain=$h
      if [ "$domain" = "$h" ]; then
        _sub_domain="@"
      else
        _sub_domain=${domain%."$h"}
      fi
      return 0
    fi
    case "$h" in
    *.*) h=${h#*.} ;;
    *) return 1 ;;
    esac
  done
}

# Ids of TXT records with this name and this exact value.
_mizban_find_records() {
  _mizban_record_ids=""
  if ! _mizban_rest GET "domains/$_domain_id/dns"; then
    _mizban_api_error "listing DNS records for $_domain"
    return 1
  fi
  _mizban_record_ids=$(_mizban_txt_ids)
  _debug "Matching TXT record ids" "$_mizban_record_ids"
  return 0
}

_mizban_rest() {
  _mizban_method=$1
  _mizban_ep=$2
  _mizban_data=$3
  _mizban_code=""
  _mizban_message=""
  _mizban_fields=""

  # _get/_post run in a command substitution. Initialize the header file here,
  # or the status line stays in that subshell.
  _inithttp
  export _H1="Authorization: Bearer $Mizban_Token"
  export _H2="Accept: application/json"
  export _H3=""
  export _H4=""
  export _H5=""
  if [ "$_mizban_method" != "GET" ]; then
    export _H3="Content-Type: application/json"
  fi

  if [ "$_mizban_method" = "GET" ]; then
    response=$(_get "$MIZBAN_API/$_mizban_ep") || return 1
  else
    response=$(_post "$_mizban_data" "$MIZBAN_API/$_mizban_ep" "" "$_mizban_method") || return 1
  fi

  _mizban_code=$(grep "^HTTP/" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")
  _debug "MizbanCloud HTTP status" "$_mizban_code"
  response=$(printf "%s" "$response" | _normalizeJson)
  _secure_debug2 response "$response"
  _mizban_message=$(printf "%s" "$response" | sed -n 's/.*"message" *: *"\([^"]*\)".*/\1/p' | _head_n 1)
  _mizban_fields=$(printf "%s" "$response" | sed -n 's/.*"fields" *: *{\([^}]*\)}.*/\1/p' | _head_n 1 | tr -d '"')
  _mizban_ok=$(printf "%s" "$response" | sed -n 's/.*"success" *: *\([A-Za-z]*\).*/\1/p' | _head_n 1)
  if [ "$_mizban_code" = "200" ] || [ "$_mizban_code" = "201" ]; then
    [ "$_mizban_ok" = "true" ] && return 0
  fi
  return 1
}

_mizban_api_error() {
  if [ "$_mizban_code" = "401" ]; then
    _err "MizbanCloud rejected the API token."
    _err "Create a token in the MizbanCloud panel and export Mizban_Token."
  elif [ "$_mizban_code" ]; then
    _err "MizbanCloud request failed while $1 (HTTP $_mizban_code)."
  else
    _err "Could not reach the MizbanCloud API while $1."
  fi
  if [ "$_mizban_message" ]; then
    _err "MizbanCloud says: $_mizban_message"
  fi
  if [ "$_mizban_fields" ]; then
    _err "MizbanCloud fields: $_mizban_fields"
  fi
}

# One "id name" line per domain. Objects in this API start with "id".
_mizban_pairs() {
  _mizban_chunks | while IFS= read -r _mizban_line; do
    _mizban_id=$(printf "%s" "$_mizban_line" | sed -n 's/^"id" *: *\([0-9][0-9]*\).*/\1/p' | _head_n 1)
    _mizban_name=$(printf "%s" "$_mizban_line" | sed -n 's/.*"name" *: *"\([^"]*\)".*/\1/p' | _head_n 1 | _lower_case)
    if [ "$_mizban_id" ] && [ "$_mizban_name" ]; then
      printf "%s %s\n" "$_mizban_id" "$_mizban_name"
    fi
  done
}

_mizban_txt_ids() {
  _mizban_chunks | while IFS= read -r _mizban_line; do
    _mizban_type=$(printf "%s" "$_mizban_line" | sed -n 's/.*"type" *: *"\([^"]*\)".*/\1/p' | _head_n 1 | _lower_case)
    [ "$_mizban_type" = "txt" ] || continue
    _mizban_name=$(printf "%s" "$_mizban_line" | sed -n 's/.*"name" *: *"\([^"]*\)".*/\1/p' | _head_n 1 | _lower_case)
    _mizban_text=$(printf "%s" "$_mizban_line" | sed -n 's/.*"content" *: *"\([^"]*\)".*/\1/p' | _head_n 1)
    if _mizban_same_name "$_mizban_name" && [ "$_mizban_text" = "$txtvalue" ]; then
      _mizban_id=$(printf "%s" "$_mizban_line" | sed -n 's/^"id" *: *\([0-9][0-9]*\).*/\1/p' | _head_n 1)
      [ "$_mizban_id" ] && printf "%s\n" "$_mizban_id"
    fi
  done
}

_mizban_chunks() {
  printf "%s\n" "$response" | sed 's/"id"/\
"id"/g'
}

# "@" is stored back as the zone name.
_mizban_same_name() {
  if [ "$_sub_domain" = "@" ]; then
    [ "$1" = "@" ] || [ "$1" = "$_domain" ]
  else
    [ "$1" = "$_sub_domain" ]
  fi
}
