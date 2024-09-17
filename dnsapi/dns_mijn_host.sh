#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_mijnhost_info='mijn.host
Domains: mijn.host
Site: mijn.host
Docs: https://mijn.host/api/doc/api-3563900
Options:
 MIJN_HOST_API_KEY API Key
 MIJN_HOST_ENDPOINT_API API Endpoint URL. E.g. "https://mijn.host/api/v2"
'

########  Public functions ###################### Constants for your mijn-host API
MIJN_HOST_API="https://api.mijn-host.com/v1"

# Add TXT record for domain verification
dns_mijn_host_add() {
  fulldomain=$1
  txtvalue=$2

  MIJN_HOST_API_KEY="${MIJN_HOST_API_KEY:-$(_readaccountconf_mutable MIJN_HOST_API_KEY)}"
  if [ -z "$MIJN_HOST_API_KEY" ]; then
    MIJN_HOST_API_KEY=""
    _err "You haven't specified mijn-host API key yet."
    _err "Please set it and try again."
    return 1
  fi

  # Save the API key for future use
  _saveaccountconf_mutable MIJN_HOST_API_KEY "$MIJN_HOST_API_KEY"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _debug "Add TXT record"
  
  # Build the payload for the API
  data="{\"type\": \"TXT\", \"name\": \"$subdomain\", \"content\": \"$txtvalue\", \"ttl\": 120}"

  export _H1="Authorization: Bearer $MIJN_HOST_API_KEY"
  export _H2="Content-Type: application/json"
  
  # Use the _post method to make the API request
  response="$(_post "$data" "$MIJN_HOST_API/zones/$root_zone/records")"

  if _contains "$response" "error"; then
    _err "Error adding TXT record: $response"
    return 1
  fi

  _info "TXT record added successfully"
  return 0
}

# Remove TXT record after verification
dns_mijn_host_rm() {
  fulldomain=$1
  txtvalue=$2

  MIJN_HOST_API_KEY="${MIJN_HOST_API_KEY:-$(_readaccountconf_mutable MIJN_HOST_API_KEY)}"
  if [ -z "$MIJN_HOST_API_KEY" ]; then
    MIJN_HOST_API_KEY=""
    _err "You haven't specified mijn-host API key yet."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _debug "Removing TXT record"
  
  # Build the payload for the API
  export _H1="Authorization: Bearer $MIJN_HOST_API_KEY"
  
  # Use the _get method to find the record ID for deletion
  record_id="$(_get "$MIJN_HOST_API/zones/$root_zone/records?type=TXT&name=$subdomain")"

  if [ -z "$record_id" ]; then
    _err "TXT record not found"
    return 1
  fi

  # Delete the TXT record
  response="$(_post "" "$MIJN_HOST_API/zones/$root_zone/records/$record_id" "DELETE")"

  if _contains "$response" "error"; then
    _err "Error removing TXT record: $response"
    return 1
  fi

  _info "TXT record removed successfully"
  return 0
}

# Helper function to detect the root zone
_get_root() {
  domain=$1
  i=2
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-)
    if [ -z "$h" ]; then
      return 1
    fi

    if _contains "$(dig ns $h)" "mijn-host.com"; then
      root_zone="$h"
      subdomain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}
