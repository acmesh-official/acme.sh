#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_bh_info='Best-Hosting.cz
Site: best-hosting.cz
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_bh
Options:
 BH_API_USER API User identifier.
 BH_API_KEY API Secret key.
Issues: github.com/acmesh-official/acme.sh/issues/6854
Author: @heximcz
'

BH_Api="https://best-hosting.cz/api/v1"

########  Public functions #####################

# Usage: dns_bh_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_bh_add() {
  fulldomain=$1
  txtvalue=$2

  # --- 1. Credentials ---
  BH_API_USER="${BH_API_USER:-$(_readaccountconf_mutable BH_API_USER)}"
  BH_API_KEY="${BH_API_KEY:-$(_readaccountconf_mutable BH_API_KEY)}"

  if [ -z "$BH_API_USER" ] || [ -z "$BH_API_KEY" ]; then
    BH_API_USER=""
    BH_API_KEY=""
    _err "You must specify BH_API_USER and BH_API_KEY."
    return 1
  fi

  _saveaccountconf_mutable BH_API_USER "$BH_API_USER"
  _saveaccountconf_mutable BH_API_KEY "$BH_API_KEY"

  # --- 2. Add TXT record ---
  _info "Adding TXT record for $fulldomain"

  json_payload="{\"fulldomain\":\"$fulldomain\",\"txtvalue\":\"$txtvalue\"}"
  if ! _bh_rest POST "dns" "$json_payload"; then
    _err "Failed to add DNS record."
    return 1
  fi

  _norm_add=$(printf "%s" "$response" | tr -d '[:space:]')
  if ! _contains "$_norm_add" '"status":"success"'; then
    _err "API error: $response"
    return 1
  fi

  record_id=$(printf "%s" "$_norm_add" | _egrep_o '"id":[0-9]+' | cut -d':' -f2)
  _debug record_id "$record_id"

  if [ -z "$record_id" ]; then
    _err "Could not parse record ID from response."
    return 1
  fi

  # Sanitize key — replace dots and hyphens with underscores
  _conf_key=$(printf "%s" "BH_record_ids_${fulldomain}" | tr '.-' '_')

  # Wildcard support: store space-separated list of IDs
  # First call stores "111", second call stores "111 222"
  _existing_ids=$(_readdomainconf "$_conf_key")
  if [ -z "$_existing_ids" ]; then
    _savedomainconf "$_conf_key" "$record_id"
  else
    _savedomainconf "$_conf_key" "$_existing_ids $record_id"
  fi

  _info "DNS TXT record added successfully."
  return 0
}

# Usage: dns_bh_rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_bh_rm() {
  fulldomain=$1
  txtvalue=$2

  # --- 1. Credentials ---
  BH_API_USER="${BH_API_USER:-$(_readaccountconf_mutable BH_API_USER)}"
  BH_API_KEY="${BH_API_KEY:-$(_readaccountconf_mutable BH_API_KEY)}"

  if [ -z "$BH_API_USER" ] || [ -z "$BH_API_KEY" ]; then
    BH_API_USER=""
    BH_API_KEY=""
    _err "You must specify BH_API_USER and BH_API_KEY."
    return 1
  fi

  # Sanitize key — same as in add
  _conf_key=$(printf "%s" "BH_record_ids_${fulldomain}" | tr '.-' '_')

  # --- 2. Load stored record ID(s) ---
  _existing_ids=$(_readdomainconf "$_conf_key")
  _debug _existing_ids "$_existing_ids"

  if [ -z "$_existing_ids" ]; then
    _err "Could not find record ID for $fulldomain."
    return 1
  fi

  record_id=""
  _remaining_ids=""

  # Find the record ID that matches both the name and txtvalue
  for _id in $_existing_ids; do
    if ! _bh_rest GET "dns/$_id"; then
      _debug "Failed to query record id $_id, skipping."

      # Keep it in the list so a later run can try again
      if [ -z "$_remaining_ids" ]; then
        _remaining_ids="$_id"
      else
        _remaining_ids="$_remaining_ids $_id"
      fi
      continue
    fi

    _match_name=0
    _match_content=0
    _norm_response=$(printf "%s" "$response" | tr -d '[:space:]')

    case "$_norm_response" in
    *"\"name\":\"$fulldomain\""*)
      _match_name=1
      ;;
    esac
    case "$_norm_response" in
    *"\"content\":\"$txtvalue\""*)
      _match_content=1
      ;;
    esac

    if [ "$_match_name" -eq 1 ] && [ "$_match_content" -eq 1 ]; then
      record_id="$_id"
      _debug "Matched record id" "$record_id"
      # Do not add this ID to _remaining_ids; it will be deleted
      continue
    fi

    # Not a match — keep ID for potential future cleanups
    if [ -z "$_remaining_ids" ]; then
      _remaining_ids="$_id"
    else
      _remaining_ids="$_remaining_ids $_id"
    fi
  done

  if [ -z "$record_id" ]; then
    _err "Could not find matching TXT record for $fulldomain with the given value."
    return 1
  fi

  # --- 3. Delete record ---
  _info "Removing TXT record for $fulldomain"

  if ! _bh_rest DELETE "dns/$record_id"; then
    _err "Failed to remove DNS record."
    return 1
  fi

  # Update stored list — remove used ID
  if [ -z "$_remaining_ids" ]; then
    _cleardomainconf "$_conf_key"
  else
    _savedomainconf "$_conf_key" "$_remaining_ids"
  fi

  _info "DNS TXT record removed successfully."
  return 0
}

####################  Private functions #####################

_bh_rest() {
  m="$1"
  ep="$2"
  data="$3"
  _debug "$ep"

  _credentials="$(printf "%s:%s" "$BH_API_USER" "$BH_API_KEY" | _base64)"

  export _H1="Authorization: Basic $_credentials"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  if [ "$m" = "GET" ]; then
    response="$(_get "$BH_Api/$ep")"
  else
    _debug data "$data"
    response="$(_post "$data" "$BH_Api/$ep" "" "$m")"
  fi

  if [ "$?" != "0" ]; then
    _err "Error calling $m $BH_Api/$ep"
    return 1
  fi

  _debug2 response "$response"
  return 0
}
