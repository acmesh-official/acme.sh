#!/usr/bin/env sh
# Script to deploy a certificate to FortiGate via API and set it as the current web GUI certificate.
#
# FortiGate's native ACME integration does not support wildcard certificates,
# and is not supported if you have a custom management web port (eg. DNAT web traffic).
#
# REQUIRED:
#     export FGT_HOST="fortigate_hostname-or-ip"
#     export FGT_TOKEN="fortigate_api_token"
#
# OPTIONAL:
#     export FGT_PORT="10443"             # Custom HTTPS port (defaults to 443 if not set)
#
# This script is intended for use as an acme.sh deploy hook.
#
# Run `acme.sh --deploy -d example.com --deploy-hook fortigate --insecure` to use this script.
# `--insecure` is required to allow acme.sh to connect to the FortiGate API over HTTPS without a pre-existing valid certificate.

# Function to parse response
parse_response() {
  response="$1"
  func="$2"
  status=$(echo "$response" | grep -o '"status":[ ]*"[^"]*"' | sed 's/"status":[ ]*"\([^"]*\)"/\1/')
  if [ "$status" != "success" ]; then
    _err "[$func] Operation failed. Deploy with --insecure if current certificate is invalid. Try deploying with --debug to troubleshoot."
    return 1
  else
    _debug "[$func] Operation successful."
    return 0
  fi
}

# Function to deploy base64-encoded certificate to firewall
deployer() {
  cert_base64=$(_base64 <"$_cfullchain" | tr -d '\n')
  key_base64=$(_base64 <"$_ckey" | tr -d '\n')
  payload=$(
    cat <<EOF
{
  "type": "regular",
  "scope": "global",
  "certname": "$_cdomain",
  "key_file_content": "$key_base64",
  "file_content": "$cert_base64"
}
EOF
  )
  url="https://${FGT_HOST}:${FGT_PORT}/api/v2/monitor/vpn-certificate/local/import"
  _debug "Uploading certificate via URL: $url"
  _H1="Authorization: Bearer $FGT_TOKEN"
  response=$(_post "$payload" "$url" "" "POST" "application/json")
  _debug "FortiGate API Response: $response"
  parse_response "$response" "Deploying certificate" || return 1
}

# Function to upload CA certificate to firewall (FortiGate doesn't automatically extract CA from fullchain)
upload_ca_cert() {
  ca_base64=$(_base64 <"$_cca" | tr -d '\n')
  payload=$(
    cat <<EOF
{
  "import_method": "file",
  "scope": "global",
  "file_content": "$ca_base64"
}
EOF
  )
  url="https://${FGT_HOST}:${FGT_PORT}/api/v2/monitor/vpn-certificate/ca/import"
  _debug "Uploading CA certificate via URL: $url"
  _H1="Authorization: Bearer $FGT_TOKEN"
  response=$(_post "$payload" "$url" "" "POST" "application/json")
  _debug "FortiGate API CA Response: $response"
  # Handle response -328 (CA already exists)
  if echo "$response" | grep -q '"error":[ ]*-328'; then
    _debug "CA certificate already exists. Skipping CA upload."
    return 0
  fi
  parse_response "$response" "Deploying CA certificate" || return 1
}

# Function to activate the new certificate
set_active_web_cert() {
  payload=$(
    cat <<EOF
{
  "admin-server-cert": "$_cdomain"
}
EOF
  )
  url="https://${FGT_HOST}:${FGT_PORT}/api/v2/cmdb/system/global"
  _debug "Setting GUI certificate..."
  _H1="Authorization: Bearer $FGT_TOKEN"
  response=$(_post "$payload" "$url" "" "PUT" "application/json")
  parse_response "$response" "Assigning active certificate" || return 1
}

# Function to clean up previous certificate (if exists)
cleanup_previous_certificate() {
  _getdeployconf FGT_LAST_CERT

  if [ -n "$FGT_LAST_CERT" ] && [ "$FGT_LAST_CERT" != "$_cdomain" ]; then
    _debug "Found previously deployed certificate: $FGT_LAST_CERT. Deleting it."

    url="https://${FGT_HOST}:${FGT_PORT}/api/v2/cmdb/vpn.certificate/local/${FGT_LAST_CERT}"

    _H1="Authorization: Bearer $FGT_TOKEN"
    response=$(_post "" "$url" "" "DELETE" "application/json")
    _debug "Delete certificate API response: $response"

    parse_response "$response" "Delete previous certificate" || return 1
  else
    _debug "No previous certificate found or new cert is the same as the previous one."
  fi
}

# Main function.
fortigate_deploy() {
  # Create new certificate name with date appended (cannot directly overwrite old certificate)
  _cdomain="$(echo "$1" | sed 's/*/WILDCARD_/g')_$(date -u +"%Y-%m-%d")"
  _ckey="$2"
  _cca="$4"
  _cfullchain="$5"

  if [ ! -f "$_ckey" ] || [ ! -f "$_cfullchain" ]; then
    _err "Valid key and/or certificate not found."
    return 1
  fi

  # Save required environment variables if not already stored.
  for var in FGT_HOST FGT_TOKEN FGT_PORT; do
    if [ "$(eval echo \$$var)" ]; then
      _debug "Detected ENV variable $var. Saving to file."
      _savedeployconf "$var" "$(eval echo \$$var)" 1
    else
      _debug "Attempting to load variable $var from file."
      _getdeployconf "$var"
    fi
  done

  if [ -z "$FGT_HOST" ] || [ -z "$FGT_TOKEN" ]; then
    _err "FGT_HOST and FGT_TOKEN must be set."
    return 1
  fi

  FGT_PORT="${FGT_PORT:-443}"
  _debug "Using FortiGate port: $FGT_PORT"

  # Deploy new certificate and set it as active.
  deployer || return 1

  # Upload base64-encoded CA certificate
  if [ -n "$_cca" ] && [ -f "$_cca" ]; then
    upload_ca_cert || return 1
  else
    _debug "No CA certificate provided."
  fi

  set_active_web_cert || return 1

  # Cleanup previous certificate
  cleanup_previous_certificate

  # Store new certificate name for cleanup on next renewal
  _savedeployconf "FGT_LAST_CERT" "$_cdomain" 1
}
