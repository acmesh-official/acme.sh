# REQUIRED:
#     export FMG_HOST="fortimanager_hostname-or-ip"
#     export FMG_TOKEN="fortimanager_api_token"
#
# OPTIONAL:
#     export FMG_PORT="10443"             # Custom HTTPS port (defaults to 443 if not set)
#
# Run `acme.sh --deploy -d example.com --deploy-hook fortimanager --insecure` to use this script.
# OPTIONAL:
#     export FMG_PORT="10443"             # Custom HTTPS port (defaults to 443 if not set)
#
# Run `acme.sh --deploy -d example.com --deploy-hook fortimanager --insecure` to use this script.
# `--insecure` is required on first run if not already using a valid SSL certificate on firewall.

# Function to parse a FortiGate API response
_fortimanager_parse_response() {
  _fortimanager_response="$1"
  _fortimanager_func="$2"
  _fortimanager_status=$(echo "$_fortimanager_response" | _egrep_o '"status":[ ]*"[^"]*"' | cut -d '"' -f 4)

  if [ "$_fortimanager_status" != "success" ]; then
    return 1
  fi

  _debug "[$_fortimanager_func] Operation successful."
  return 0
}

# Function to deploy a base64-encoded certificate to the FortiManager
_fortimanager_deployer() {
  _fortimanager_cert_base64=$(_base64 <"$_fortimanager_cfullchain" | tr -d '\n')
  _fortimanager_key_base64=$(_base64 <"$_fortimanager_ckey" | tr -d '\n')
  _fortimanager_payload=$(
    cat <<EOF
{
        "method": "add",
        "params": [
        {
                "data": [
                {
                        "certificate": [
                                "$_fortimanager_cert_base64"
                        ],
                        "name": "$_fortimanager_cert_name",
                        "private-key": [
                                "$_fortimanager_key_base64"
                        ]
                }
                ],
                "url": "/cli/global/system/certificate/local"
        }
        ]
}
EOF
  )

  _fortimanager_url="https://${FMG_HOST}:${FMG_PORT}/jsonrpc"
  _debug "Uploading certificate via URL: $_fortimanager_url"

  _H1="Authorization: Bearer $FMG_TOKEN"
  _fortimanager_response=$(_post "$_fortimanager_payload" "$_fortimanager_url" "" "POST" "application/json")
  _debug "FortiManager API Response: $_fortimanager_response"

  _fortimanager_parse_response "$_fortimanager_response" "Deploying certificate" || return 1
}

# Function to upload a CA certificate to the firewall
# FortiGate does not automatically extract the CA from the full chain.
_fortimanager_upload_ca_cert() {
  _fortimanager_ca_base64=$(_base64 <"$_fortimanager_cca" | tr -d '\n')
  _fortimanager_payload=$(
    cat <<EOF
{
  "method": "add",
  "params": [
    {
      "data": [
        {
          "ca": [
            "$_fortimanager_ca_base64"
          ],
          "name": "$_fortimanager_ca_name"
        }
      ],
      "url": "/cli/global/system/certificate/ca"
    }
  ],
}
EOF
  )

  _fortimanager_url="https://${FMG_HOST}:${FMG_PORT}/jsonrpc"
  _debug "Uploading CA certificate via URL: $_fortimanager_url"

  _H1="Authorization: Bearer $FMG_TOKEN"
  _fortimanager_response=$(_post "$_fortimanager_payload" "$_fortimanager_url" "" "POST" "application/json")
  _debug "FortiManager API CA Response: $_fortimanager_response"

  # FortiManager error -328 means that the CA certificate already exists.
  #if echo "$_fortimanager_response" | grep -q '"error":[ ]*-328'; then
  #  _debug "CA certificate already exists. Skipping CA upload."
  #  return 0
  #fi

  _fortimanager_parse_response "$_fortimanager_response" "Deploying CA certificate" || return 1
}

# Function to activate the new certificate
_fortimanager_set_active_web_cert() {
  _fortimanager_payload=$(
    cat <<EOF
{
  "admin-server-cert": "$_fortimanager_cert_name"
}
EOF
  )

  _fortimanager_url="https://${FMG_HOST}:${FMG_PORT}/jsonrpc"
  _debug "Setting GUI certificate..."

  _H1="Authorization: Bearer $FMG_TOKEN"
  _fortimanager_response=$(_post "$_fortimanager_payload" "$_fortimanager_url" "" "PUT" "application/json")

  _fortimanager_parse_response "$_fortimanager_response" "Assigning active certificate" || return 1
}

# Function to clean up the previously deployed certificate
_fortimanager_cleanup_previous_certificate() {
  _getdeployconf FMG_LAST_CERT

  if [ -n "$FMG_LAST_CERT" ] && [ "$FMG_LAST_CERT" != "$_fortimanager_cert_name" ]; then
    _debug "Found previously deployed certificate: $FMG_LAST_CERT. Deleting it."

    _fortimanager_url="https://${FMG_HOST}:${FMG_PORT}/api/v2/cmdb/vpn.certificate/local/${FMG_LAST_CERT}"
    _H1="Authorization: Bearer $FMG_TOKEN"
    _fortimanager_response=$(_post "" "$_fortimanager_url" "" "DELETE" "application/json")
    _debug "Delete certificate API response: $_fortimanager_response"

    _fortimanager_parse_response "$_fortimanager_response" "Delete previous certificate" || return 1
  else
    _debug "No previous certificate found."
  fi
}

# Main deploy-hook function
fortimanager_deploy() {
  # Include date and time to ensure unique names.
  _fortimanager_cert_name="$(echo "$1" | sed 's/*/WILDCARD_/g')_$(date -u +"%Y-%m-%d_%H-%M-%S")"
  _fortimanager_ckey="$2"
  _fortimanager_cca="$4"
  _fortimanager_cfullchain="$5"

  if [ ! -f "$_fortimanager_ckey" ] || [ ! -f "$_fortimanager_cfullchain" ]; then
    _err "Valid key and/or certificate not found."
    return 1
  fi

  # Save required environment variables if set; otherwise load saved values.
  for _fortimanager_var in FMG_HOST FMG_TOKEN FMG_PORT; do
    if [ -n "$(eval echo "\$$_fortimanager_var")" ]; then
      _debug "Detected ENV variable $_fortimanager_var. Saving to file."
      _savedeployconf "$_fortimanager_var" "$(eval echo "\$$_fortimanager_var")" 1
    else 
      _debug "Attempting to load variable $_fortimanager_var from file."
# Main deploy-hook function
fortimanager_deploy() {
  # Include date and time to ensure unique names.
  _fortimanager_cert_name="$(echo "$1" | sed 's/*/WILDCARD_/g')_$(date -u +"%Y-%m-%d_%H-%M-%S")"
  _fortimanager_ckey="$2"
  _fortimanager_cca="$4"
  _fortimanager_cfullchain="$5"

  if [ ! -f "$_fortimanager_ckey" ] || [ ! -f "$_fortimanager_cfullchain" ]; then
    _err "Valid key and/or certificate not found."
    return 1
  fi

  # Save required environment variables if set; otherwise load saved values.
  for _fortimanager_var in FMG_HOST FMG_TOKEN FMG_PORT; do
    if [ -n "$(eval echo "\$$_fortimanager_var")" ]; then
      _debug "Detected ENV variable $_fortimanager_var. Saving to file."
      _savedeployconf "$_fortimanager_var" "$(eval echo "\$$_fortimanager_var")" 1
    else
      _debug "Attempting to load variable $_fortimanager_var from file."
      _getdeployconf "$_fortimanager_var"
    fi
  done

  if [ -z "$FMG_HOST" ] || [ -z "$FMG_TOKEN" ]; then
    _err "FMG_HOST and FMG_TOKEN must be set."
    return 1
  fi

  FMG_PORT="${FMG_PORT:-443}"
  _debug "Using FortiManager port: $FMG_PORT"