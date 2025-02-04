#!/usr/bin/env sh
# Script to deploy a certificate to FortiGate via API and set it as the current web GUI certificate.
#
# REQUIRED:
#     export FGT_HOST="fortigate_hostname-or-ip"
#     export FGT_TOKEN="fortigate_api_token"
#
# OPTIONAL:
#     export FGT_PORT="10443"             # Custom HTTPS port (defaults to 443 if not set)
#
# Run `acme.sh --deploy -d example.com --deploy-hook fortigate --insecure` to use this script.
# '--insecure' is required to allow acme.sh to connect to the FortiGate API over HTTPS without a pre-existing valid certificate.
#

# Function to parse response from the firewall
parse_response() {
  status=$(echo "$1" | grep -o '"status":[ ]*"[^"]*"' | sed 's/"status":[ ]*"\([^"]*\)"/\1/')
  error_code=$(echo "$1" | grep -o '"error":[ ]*[-0-9]*' | sed 's/"error":[ ]*\([-0-9]*\)/\1/')
  http_status=$(echo "$1" | grep -o '"http_status":[ ]*[0-9]*' | sed 's/"http_status":[ ]*\([0-9]*\)/\1/')

  if [ "$status" != "success" ]; then
    _err "FortiGate error: HTTP $http_status, Code $error_code"
    return 1
  else
    _debug "Operation successful."
    return 0
  fi
}

# Function to deploy certificate to firewall
deployer() {
  cert_base64=$(cat "$_cfullchain" | _base64)
  key_base64=$(cat "$_ckey" | _base64)

  payload=$(cat <<EOF
{
  "type": "regular",
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
  parse_response "$response"
}

# Function to assign new cert as active server certificate
set_active_web_cert() {
  payload=$(cat <<EOF
{
  "admin-server-cert": "$_cdomain"
}
EOF
)
  url="https://${FGT_HOST}:${FGT_PORT}/api/v2/cmdb/system/global"
  _debug "Setting GUI certificate.."

  _H1="Authorization: Bearer $FGT_TOKEN"

  response=$(_post "$payload" "$url" "" "PUT" "application/json")
  parse_response "$response"
}

# Main function
fortigate_deploy() {
  _cdomain="$(echo "$1" | sed 's/*/WILDCARD_/g')_$(date -u +"%Y-%m-%d")" # Append date to certname to avoid conflicts
  _ckey="$2"
  _cfullchain="$5"

  if [ ! -f "$_ckey" ] || [ ! -f "$_cfullchain" ]; then
    _err "Valid key and/or certificate not found."
    return 1
  fi

  # Handle environment variables
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

  deployer || return 1
  set_active_web_cert || return 1
}
