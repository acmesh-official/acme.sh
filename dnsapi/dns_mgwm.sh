#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_mgwm_info='mgw-media.de
Site: mgw-media.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_mgwm
Options:
 MGWM_CUSTOMER Your customer number
 MGWM_API_HASH Your API Hash
Issues: github.com/acmesh-official/acme.sh/issues/6669
'
# Base URL for the mgw-media.de API
MGWM_API_BASE="https://api.mgw-media.de/record"

########  Public functions #####################

# This function is called by acme.sh to add a TXT record.
dns_mgwm_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using mgw-media.de DNS API for domain $fulldomain (add record)"
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"

  # Call the new private function to handle the API request.
  # The 'add' action, fulldomain, type 'txt' and txtvalue are passed.
  if _mgwm_request "add" "$fulldomain" "txt" "$txtvalue"; then
    _info "TXT record for $fulldomain successfully added via mgw-media.de API."
    _sleep 10 # Wait briefly for DNS propagation, a common practice in DNS-01 hooks.
    return 0
  else
    # Error message already logged by _mgwm_request, but a specific one here helps.
    _err "mgwm_add: Failed to add TXT record for $fulldomain."
    return 1
  fi
}
# This function is called by acme.sh to remove a TXT record after validation.
dns_mgwm_rm() {
  fulldomain=$1
  txtvalue=$2 # This txtvalue is now used to identify the specific record to be removed.
  _info "Removing TXT record for $fulldomain using mgw-media.de DNS API (remove record)"
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"

  # Call the new private function to handle the API request.
  # The 'rm' action, fulldomain, type 'txt' and txtvalue are passed.
  if _mgwm_request "rm" "$fulldomain" "txt" "$txtvalue"; then
    _info "TXT record for $fulldomain successfully removed via mgw-media.de API."
    return 0
  else
    # Error message already logged by _mgwm_request, but a specific one here helps.
    _err "mgwm_rm: Failed to remove TXT record for $fulldomain."
    return 1
  fi
}
####################  Private functions below ##################################

# _mgwm_request() encapsulates the API call logic, including
# loading credentials, setting the Authorization header, and executing the request.
# Arguments:
#   $1: action (e.g., "add", "rm")
#   $2: fulldomain
#   $3: type (e.g., "txt")
#   $4: content (the txtvalue)
_mgwm_request() {
  _action="$1"
  _fulldomain="$2"
  _type="$3"
  _content="$4"

  _debug "Calling _mgwm_request for action: $_action, domain: $_fulldomain, type: $_type, content: $_content"

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

  # Construct the API URL based on the action and provided parameters.
  _request_url="${MGWM_API_BASE}/${_action}/${_fulldomain}/${_type}/${_content}"
  _debug "Constructed mgw-media.de API URL for action '$_action': ${_request_url}"

  # Execute the HTTP GET request with the Authorization Header.
  # The 5th parameter of _get is where acme.sh expects custom HTTP headers like Authorization.
  response="$(_get "$_request_url")"
  _debug "mgw-media.de API response for action '$_action': $response"

  # Check the API response for success. The API returns "OK" on success.
  if [ "$response" = "OK" ]; then
    _info "mgw-media.de API action '$_action' for record '$_fulldomain' successful."
    return 0
  else
    _err "Failed mgw-media.de API action '$_action' for record '$_fulldomain'. Unexpected API Response: '$response'"
    return 1
  fi
}
