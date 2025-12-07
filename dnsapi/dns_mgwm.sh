#!/usr/bin/env sh
# shellcheck disable=SC2034

# DNS provider information for acme.sh
dns_mgwm_info='mgw-media.de
Site: mgw-media.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_mgwm
Options:
 MGWM_CUSTOMER Your customer number
 MGWM_API_HASH Your API Hash
Issues: github.com/acmesh-official/acme.sh
'

# Base URL for the mgw-media.de API
MGWM_API_BASE="https://api.mgw-media.de/record"

########  Public functions #####################
# This function is called by acme.sh to add a TXT record.
dns_mgwm_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using mgw-media.de DNS API for domain $fulldomain"
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"

  # Call private function to load and save environment variables and set up the Basic Auth Header.
  if ! _mgwm_init_env; then
    return 1
  fi

  # Construct the API URL for adding a record.
  #_add_url="${MGWM_API_BASE}/add/${fulldomain}/txt/${txtvalue}"
  _add_url="${MGWM_API_BASE}.php?action=add&fulldomain=${fulldomain}&type=txt&content=${txtvalue}"
  _debug "Calling MGWM ADD URL: ${_add_url}"

  # Execute the HTTP GET request with the Authorization Header.
  # The 5th parameter of _get is where acme.sh expects custom HTTP headers like Authorization.
  response="$(_get "$_add_url")"
  _debug "MGWM add response: $response"

  # Check the API response for success. The API returns "OK" on success.
  if [ "$response" = "OK" ]; then
      _info "TXT record for $fulldomain successfully added via MGWM API."
      _sleep 10 # Wait briefly for DNS propagation, a common practice in DNS-01 hooks.
      return 0
  else
      _err "mgwm_add: Failed to add TXT record for $fulldomain. Unexpected API Response: '$response'"
      return 1
  fi
}

# This function is called by acme.sh to remove a TXT record after validation.
dns_mgwm_rm() {
  fulldomain=$1
  txtvalue=$2 # This txtvalue is now used to identify the specific record to be removed.

  _info "Removing TXT record for $fulldomain using mgw-media.de DNS API"
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"

  # Call private function to load and save environment variables and set up the Basic Auth Header.
  if ! _mgwm_init_env; then
    return 1
  fi

  # Construct the API URL for removing a record.
  # To delete a specific record by its value (as required by ACME v2 for multiple TXT records),
  # the txtvalue must be part of the URL, similar to the add action.
  #_rm_url="${MGWM_API_BASE}/rm/${fulldomain}/txt/${txtvalue}"
  _rm_url="${MGWM_API_BASE}.php?action=rm&fulldomain=${fulldomain}&type=txt&content=${txtvalue}"
  _debug "Calling MGWM RM URL: ${_rm_url}"

  # Execute the HTTP GET request with the Authorization Header.
  response="$(_get "$_rm_url")"
  _debug "MGWM rm response: $response"

  # Check the API response for success. The API returns "OK" on success.
  if [ "$response" = "OK" ]; then
      _info "TXT record for $fulldomain successfully removed via MGWM API."
      return 0
  else
      _err "mgwm_rm: Failed to remove TXT record for $fulldomain. Unexpected API Response: '$response'"
      return 1
  fi
}

####################  Private functions below ##################################

# _mgwm_init_env() loads the mgw-media.de API credentials (customer number and hash)
# from environment variables or acme.sh's configuration, saves them, and
# prepares the global _H1 variable for Basic Authorization header.
_mgwm_init_env() {
  # Load credentials from environment or acme.sh config
  MGWM_CUSTOMER="${MGWM_CUSTOMER:-$(_readaccountconf_mutable MGWM_CUSTOMER)}"
  MGWM_API_HASH="${MGWM_API_HASH:-$(_readaccountconf_mutable MGWM_API_HASH)}"

  # Check if credentials are set
  if [ -z "$MGWM_CUSTOMER" ] || [ -z "$MGWM_API_HASH" ]; then
    _err "You didn't specify one or more of MGWM_CUSTOMER or MGWM_API_HASH."
    _err "Please check these environment variables and try again."
    return 1
  fi

  # Save credentials for automatic renewal and future calls
  _saveaccountconf_mutable MGWM_CUSTOMER "$MGWM_CUSTOMER"
  _saveaccountconf_mutable MGWM_API_HASH "$MGWM_API_HASH"

  # Create the Basic Auth Header. acme.sh's _base64 function is used for encoding.
  _credentials="$(printf "%s:%s" "$MGWM_CUSTOMER" "$MGWM_API_HASH" | _base64)"
  export _H1="Authorization: Basic $_credentials"
  _debug "Set Authorization Header: Basic <credentials_encoded>" # Log debug message without sensitive credentials
  return 0
}
