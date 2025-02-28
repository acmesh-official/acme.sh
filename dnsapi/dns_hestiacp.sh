#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_hestiacp_info='HestiaCP DNS API
Site: https://hestiacp.com
Docs: https://github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_hestiacp

Options:
  HESTIA_HOST    The HestiaCP panel URL (e.g., https://panel.domain.com:8083)
  HESTIA_ACCESS  The HestiaCP API access key
  HESTIA_SECRET  The HestiaCP API secret key
  HESTIA_USER    Your HestiaCP username (defaults to "admin")

API Key Setup:
  1. Log in to HestiaCP panel as admin
  2. Go to Server -> Configure -> API
  3. Generate a key pair with "update-dns-records" permission
  4. Copy Host, Access Key, and Secret Key
  5. Login to our HestiaCP server as root, and go to /usr/local/hestia/data/api
  6. The file "update-dns-records" should contain this line in order for this script to work:
     ROLE='user'
     COMMANDS='v-list-dns-records,v-change-dns-record,v-delete-dns-record,v-add-dns-record'
     By default, only v-list-dns-records and v-change-dns-record are enabled.

NOTES: for wildcard certificates to work, you need to use LetsEncrypt V2 provider, not Alpha ZeroSSL which is default in acme.sh

Example Usage:
  export HESTIA_HOST="https://panel.domain.com:8083"
  export HESTIA_ACCESS="your_access_key"
  export HESTIA_SECRET="your_secret_key"
  export HESTIA_USER="your_username"
  acme.sh --issue -d example.com -d *.example.com --dns dns_hestiacp

Author: Radu Malica <radu.malica@gmail.com> https://github.com/radumalica/
Issues: https://github.com/acmesh-official/acme.sh/issues/6251
'

########  Public functions #####################

# Usage: add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_hestiacp_add() {
  fulldomain=$1
  txtvalue=$2

  HESTIA_HOST="${HESTIA_HOST:-$(_readaccountconf_mutable HESTIA_HOST)}"
  HESTIA_ACCESS="${HESTIA_ACCESS:-$(_readaccountconf_mutable HESTIA_ACCESS)}"
  HESTIA_SECRET="${HESTIA_SECRET:-$(_readaccountconf_mutable HESTIA_SECRET)}"
  HESTIA_USER="${HESTIA_USER:-$(_readaccountconf_mutable HESTIA_USER)}"
  
  if [ -z "$HESTIA_HOST" ] || [ -z "$HESTIA_ACCESS" ] || [ -z "$HESTIA_SECRET" ]; then
    _err "Missing required HestiaCP credentials"
    return 1
  fi

  # Remove trailing slash if present
  HESTIA_HOST="${HESTIA_HOST%/}"

  # Set default user if not provided
  [ -z "$HESTIA_USER" ] && HESTIA_USER="admin"

  # Save the credentials to the account conf file
  _saveaccountconf_mutable HESTIA_HOST "$HESTIA_HOST"
  _saveaccountconf_mutable HESTIA_ACCESS "$HESTIA_ACCESS"
  _saveaccountconf_mutable HESTIA_SECRET "$HESTIA_SECRET"
  [ "$HESTIA_USER" != "admin" ] && _saveaccountconf_mutable HESTIA_USER "$HESTIA_USER"

  # Validate hostname format
  if ! echo "$HESTIA_HOST" | grep -qE '^https?://[^/]+$'; then
    _err "HESTIA_HOST must be a valid URL (e.g., https://panel.domain.com:8083)"
    return 1
  fi

  # Validate API keys are not obviously wrong
  if [ ${#HESTIA_ACCESS} -lt 20 ] || [ ${#HESTIA_SECRET} -lt 20 ]; then
    _err "HESTIA_ACCESS and HESTIA_SECRET must be valid API keys"
    return 1
  fi

  # Extract domain and subdomain parts
  _debug2 "Original domain: $fulldomain"
  _domain=$(echo "$fulldomain" | sed -E 's/^[^.]+\.//' | sed -E 's/^\*\.//')
  _debug2 "Using domain: $_domain"

  # Get existing TXT records
  _info "Getting DNS records for $_domain"
  _payload=$(_hestia_api_payload "v-list-dns-records" "$HESTIA_USER" "$_domain" "json")
  _debug2 "API payload: $_payload"
  response=$(_post "$_payload" "${HESTIA_HOST}/api/" "" "POST" "--connect-timeout 10")
  _ret=$?
  _debug3 "Raw API response: $response"
  _info "API response (ret=$_ret)"
  
  # Add timeout handling
  if _contains "$response" "Operation timed out"; then
    _err "API request timed out. Please try again"
    return 1
  fi

  if [ $_ret -ne 0 ]; then
    _err "Error accessing domain: $_domain"
    return 1
  fi
  
  if _contains "$response" "Error: "; then
    _err "API error: $response"
    return 1
  fi
  
  _sub="_acme-challenge"

  if ! _contains "$fulldomain" "$_sub"; then
    _err "Invalid domain format - missing $_sub prefix"
    return 1
  fi

  # First delete any existing _acme-challenge TXT records
  _info "Checking for existing _acme-challenge TXT records"
  while IFS=':' read -r id value || [ -n "$id" ]; do
    if [ -n "$id" ]; then
      if [ "$value" = "$txtvalue" ]; then
        _info "Found existing record with correct value, keeping it"
        found_exact=1
      else
        _info "Removing old _acme-challenge record $id"
        if ! _post "$(_hestia_api_payload "v-delete-dns-record" "$HESTIA_USER" "$_domain" "$id" "no")" "${HESTIA_HOST}/api/" "" "POST" "--connect-timeout 10" >/dev/null 2>&1; then
          _err "Error deleting old TXT record $id"
          return 1
        fi
        _debug2 "Successfully removed old record $id with value: $value"
      fi
    fi
  done <<EOF
$(_find_dns_records "$response" "$_sub" "TXT")
EOF

  # If we found exact match after cleanup, we're done
  if [ "$found_exact" = "1" ]; then
    _info "Using existing DNS record with correct value"
    return 0
  fi

  # Otherwise create a new record for this challenge
  _info "Adding new TXT record for challenge"
  if ! _post "$(_hestia_api_payload "v-add-dns-record" "$HESTIA_USER" "$_domain" "$_sub" "TXT" "$txtvalue" "" "" "no" "600")" "${HESTIA_HOST}/api/" "" "POST" "--connect-timeout 10" >/dev/null 2>&1; then
    _err "Error creating new TXT record"
    return 1
  fi
  _info "Successfully added new DNS-01 challenge record"
  _debug3 "Added TXT record with value: $txtvalue"
  _info "Note: Please allow time for DNS propagation"
  return 0
}

# Usage: rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_hestiacp_rm() {
  fulldomain=$1
  txtvalue=$2

  HESTIA_HOST="${HESTIA_HOST:-$(_readaccountconf_mutable HESTIA_HOST)}"
  HESTIA_ACCESS="${HESTIA_ACCESS:-$(_readaccountconf_mutable HESTIA_ACCESS)}"
  HESTIA_SECRET="${HESTIA_SECRET:-$(_readaccountconf_mutable HESTIA_SECRET)}"
  HESTIA_USER="${HESTIA_USER:-$(_readaccountconf_mutable HESTIA_USER)}"

  # Remove trailing slash if present
  HESTIA_HOST="${HESTIA_HOST%/}"

  # Set default user if not provided
  [ -z "$HESTIA_USER" ] && HESTIA_USER="admin"

  if [ -z "$HESTIA_HOST" ] || [ -z "$HESTIA_ACCESS" ] || [ -z "$HESTIA_SECRET" ]; then
    _err "Missing required HestiaCP credentials"
    return 1
  fi

  # Validate hostname format
  if ! echo "$HESTIA_HOST" | grep -qE '^https?://[^/]+$'; then
    _err "HESTIA_HOST must be a valid URL (e.g., https://panel.domain.com:8083)"
    return 1
  fi

  # Validate API keys are not obviously wrong
  if [ ${#HESTIA_ACCESS} -lt 20 ] || [ ${#HESTIA_SECRET} -lt 20 ]; then
    _err "HESTIA_ACCESS and HESTIA_SECRET must be valid API keys (length >= 20)"
    return 1
  fi

  # Extract domain parts
  _debug2 "Original domain: $fulldomain"
  
  # Define subdomain constant
  _sub="_acme-challenge"
  _debug2 "Challenge prefix: $_sub"
  
  # Validate _acme-challenge prefix
  if ! _contains "$fulldomain" "$_sub"; then
    _err "Invalid domain format - missing $_sub prefix"
    return 1
  fi
  
  # Everything after _sub. is our domain
  _domain=$(echo "$fulldomain" | sed -E 's/^[^.]+\.//' | sed -E 's/^\*\.//')
  _debug2 "Using domain: $_domain"

  # Get zone records
  _info "Getting DNS records for $_domain"
  response=$(_post "$(_hestia_api_payload "v-list-dns-records" "$HESTIA_USER" "$_domain" "json")" "${HESTIA_HOST}/api/" "" "POST" "--connect-timeout 10")
  _ret=$?
  _debug3 "Raw API response: $response"
  _info "API response (ret=$_ret)"

  # Add timeout handling
  if _contains "$response" "Operation timed out"; then
    _err "API request timed out. Please try again"
    return 1
  fi

  # Enhanced response validation
  if [ -z "$response" ]; then
    _err "Empty response received from API"
    return 1
  fi

  if [ $_ret -ne 0 ]; then
    _err "Error accessing domain: $_domain"
    return 1
  fi
  
  if _contains "$response" "Error: "; then
    _err "API error: $response"
    return 1
  fi

  # Delete matching _acme-challenge record
  _info "Checking for challenge TXT record"
  found=0
  while IFS=':' read -r id value || [ -n "$id" ]; do
    if [ -n "$id" ]; then
      if [ "$value" = "$txtvalue" ]; then
        _info "Deleting challenge record $id"
        if ! _post "$(_hestia_api_payload "v-delete-dns-record" "$HESTIA_USER" "$_domain" "$id" "no")" "${HESTIA_HOST}/api/" "" "POST" "--connect-timeout 10" >/dev/null 2>&1; then
          _err "Error deleting TXT record $id"
          return 1
        fi
        _info "Successfully removed DNS-01 challenge record"
        found=1
      else
        _debug2 "Skipping record $id with different value: $value"
      fi
    fi
  done <<EOF
$(_find_dns_records "$response" "$_sub" "TXT")
EOF

  if [ $found -eq 0 ]; then
    _info "No matching challenge record found to remove"
  fi

  return 0
}

####################  Private functions below ##################################

# Find all record IDs and values for a given name and type
# Args: response record_name type
_find_dns_records() {
  _response="$1"
  _name="$2"
  _type="$3"

  _debug2 "Parsing JSON response for '${_name}' ${_type} records"
  _debug2 "$_response"

  # Quick validation 
  if _contains "$_response" "Error: "; then
    _debug2 "Error response received: $_response"
    return 1
  fi

  # Validate we have valid JSON to parse
  if ! _contains "$_response" "{"; then
    _debug2 "Not a valid JSON response: $_response"
    return 1
  fi

  # Process JSON to find matching records
  echo "$_response" | tr -d '\n' | sed 's/},/}\n/g' | grep -o '{[^}]*"RECORD": "_acme-challenge"[^}]*}' | while read -r line; do
    id=$(echo "$line" | grep -o '"ID": "[^"]*' | cut -d'"' -f4)
    value=$(echo "$line" | grep -o '"VALUE": "[^"]*' | cut -d'"' -f4)
    echo "$id:$value"
  done
}

# Build API payload
# Args: cmd [arg1 arg2 ...]
_hestia_api_payload() {
  _cmd=$1
  shift

  export _H1="Content-Type: application/json"

  # Create JSON data exactly as expected by HestiaCP
  _data="{"
  _data="$_data\"access_key\":\"$HESTIA_ACCESS\""
  _data="$_data,\"secret_key\":\"$HESTIA_SECRET\""
  _data="$_data,\"cmd\":\"$_cmd\""
  
  _i=1
  for arg in "$@"; do
    _data="$_data,\"arg$_i\":\"$arg\""
    _i=$(_math $_i + 1)
  done

  _data="$_data}"
  printf "%s" "$_data"
}
