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
MIJN_HOST_API="https://mijn.host/api/v2"

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
  data="{\"records\": [{\"type\": \"TXT\", \"name\": \"$subdomain\", \"value\": \"$txtvalue\", \"ttl\": 120}]}"

  export _H1="API-Key: $MIJN_HOST_API_KEY"
  export _H2="Content-Type: application/json"

  # Construct the API URL
  api_url="$MIJN_HOST_API/domains/$_domain/dns"

  # Use the _post method to make the API request
  response="$(_post "$data" "$api_url" "" "PUT")"

  echo "response: $response"

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
  export _H1="API-Key: $MIJN_HOST_API_KEY"
  export _H2="Content-Type: application/json"
  
  # Construct the API URL
  api_url="$MIJN_HOST_API/domains/$_domain/dns"
  
  # Get current records
  current_records="$(_get "$MIJN_HOST_API/domains/$_domain/dns")"

  # Extract existing records into a temporary file
  echo "$current_records" | grep -o '"type":"TXT".*?}' | sed -E 's/\\//g' > /tmp/current_records.json
  
  # Build the new records without the specified TXT record
  updated_records=$(cat /tmp/current_records.json | awk -v d="$fulldomain" -v v="$txtvalue" '
    BEGIN { RS="},"; ORS="," }
    {
      if ($0 ~ d && $0 ~ v) next
      print $0
    }
  ' | sed 's/,$//')

  # Build the new payload
  data="{\"records\": [$updated_records]}"

  echo "data: $data"

  # Use the _put method to update the records
  response="$(_post "$data" "$MIJN_HOST_API/domains/$_domain/dns" "" "PUT")"
  
  if _contains "$response" "error"; then
    _err "Error updating TXT record: $response"
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

    if _contains "$(dig ns "$h")" "mijn.host"; then
      root_zone="$h"
      subdomain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}
