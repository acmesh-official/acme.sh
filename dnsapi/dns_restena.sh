#!/usr/bin/env bash

# Restena DNS API for acme.sh
# This script needs to live where the other dnsapi shell scripts are located for acme.sh
# Proxmox: /usr/share/proxmox-acme/dnsapi
# Acme: ~/.acme.sh/dnsapi
#
# Restena DNS API
# Author: @SteveClement
# Date: 31.07.2025
# AI: True
# HumMod: True
#
# Environment variables used:
#  RESTENA_TOKEN  - Your Restena API token
#  RESTENA_ZONE   - Your Restena DNS zone (e.g., example.com)
#
# Usage:
#  export RESTENA_TOKEN="your_api_token"
#  export RESTENA_ZONE="your_zone.com"
#  acme.sh --issue -d example.com --dns dns_restena

# Called by acme.sh to add a DNS TXT record
dns_restena_add() {
  fulldomain="${1}"
  txtvalue="${2}"

  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _restena_api="https://dnsgui.restena.lu/json.php"

  # Load credentials from environment or saved config
  RESTENA_TOKEN="${RESTENA_TOKEN:-$(_readaccountconf_mutable RESTENA_TOKEN)}"
  RESTENA_ZONE="${RESTENA_ZONE:-$(_readaccountconf_mutable RESTENA_ZONE)}"

  if [ -z "$RESTENA_TOKEN" ] || [ -z "$RESTENA_ZONE" ]; then
    RESTENA_TOKEN=""
    RESTENA_ZONE=""
    _err "RESTENA_TOKEN or RESTENA_ZONE not set"
    _err "Please set your Restena API token and zone and try again."
    _err "export RESTENA_TOKEN=\"your_api_token\""
    _err "export RESTENA_ZONE=\"your_zone.com\""
    return 1
  fi

  # Save credentials for future automatic renewals
  _saveaccountconf_mutable RESTENA_TOKEN "$RESTENA_TOKEN"
  _saveaccountconf_mutable RESTENA_ZONE "$RESTENA_ZONE"

  # Extract the label part by removing the zone suffix
  label="${fulldomain%.$RESTENA_ZONE}"

  # This is needed to wrap the request in double quotes
  data="\\\"$txtvalue\\\""

  _info "Adding TXT record via Restena API..."
  _debug "Zone: $RESTENA_ZONE"
  _debug "Label: $label"
  _debug "TXT value: $data"

  # Construct the JSON body for the API request
  body="{\"token\":\"$RESTENA_TOKEN\",\"zone\":\"$RESTENA_ZONE\",\"label\":\"${label}\",\"type\":\"TXT\",\"data\":\"$data\"}"
  _debug "Request body: $body"

  # Set Content-Type header
  export _H1="Content-Type: application/json"
  
  # Make the API call to add the TXT record
  response="$(_post "$body" "$_restena_api" "" "PUT")"
  _debug "API response: $response"

  # Check if the request was successful
  if [ -z "$response" ]; then
    _err "No response from Restena API"
    return 1
  fi

  # Basic success check - you may need to adjust this based on actual API responses
  if _contains "$response" "error" || _contains "$response" "Error"; then
    _err "Failed to add TXT record: $response"
    return 1
  fi

  _info "TXT record added successfully"
  return 0
}

# Called by acme.sh to remove a DNS TXT record
dns_restena_rm() {
  fulldomain="${1}"

  _debug fulldomain "$fulldomain"

  _restena_api="https://dnsgui.restena.lu/json.php"

  # Load credentials (same as in add function since they run in separate subshells)
  RESTENA_TOKEN="${RESTENA_TOKEN:-$(_readaccountconf_mutable RESTENA_TOKEN)}"
  RESTENA_ZONE="${RESTENA_ZONE:-$(_readaccountconf_mutable RESTENA_ZONE)}"

  if [ -z "$RESTENA_TOKEN" ] || [ -z "$RESTENA_ZONE" ]; then
    RESTENA_TOKEN=""
    RESTENA_ZONE=""
    _err "RESTENA_TOKEN or RESTENA_ZONE not set"
    _err "Please set your Restena API token and zone and try again."
    return 1
  fi

  # Extract the label part by removing the zone suffix
  label="${fulldomain%.$RESTENA_ZONE}"

  _info "Removing TXT record via Restena API..."
  _debug "Zone: $RESTENA_ZONE"
  _debug "Label: $label"

  # Construct the JSON body for the API request
  body="{\"token\":\"$RESTENA_TOKEN\",\"zone\":\"$RESTENA_ZONE\",\"label\":\"${label}\",\"type\":\"TXT\"}"
  _debug "Request body: $body"

  # Set Content-Type header
  export _H1="Content-Type: application/json"

  # Make the API call to remove the TXT record
  response="$(_post "$body" "$_restena_api" "" "DELETE")"
  _debug "API response: $response"

  # Check if the request was successful
  if [ -z "$response" ]; then
    _err "No response from Restena API"
    return 1
  fi

  # Basic success check - you may need to adjust this based on actual API responses
  if _contains "$response" "error" || _contains "$response" "Error"; then
    _err "Failed to remove TXT record: $response"
    return 1
  fi

  _info "TXT record removed successfully"
  return 0
}
