#!/usr/bin/env sh
# Script to deploy a certificate to FortiGate via API and set it as the current web GUI certificate.
#
# FortiGate's native ACME integration does not support wildcard certificates or domain validation,
# and is not supported if you have a custom management web port (eg. DNAT web traffic).
#
# REQUIRED:
#     export FGT_HOST="fortigate_hostname-or-ip"
#     export FGT_TOKEN="fortigate_api_token"
#
# OPTIONAL:
#     export FGT_PORT="10443"             # Custom HTTPS port (defaults to 443 if not set)
#
# Run `acme.sh --deploy -d example.com --deploy-hook fortigate --insecure` to use this script.
# `--insecure` is required on first run if not already using a valid SSL certificate on firewall.

# Function to parse a FortiGate API response
_fortigate_parse_response() {
  _fortigate_response="$1"
  _fortigate_func="$2"
  _fortigate_status=$(echo "$_fortigate_response" | _egrep_o '"status":[ ]*"[^"]*"' | cut -d '"' -f 4)

  if [ "$_fortigate_status" != "success" ]; then
    _err "[$_fortigate_func] Operation failed. Deploy with --insecure if current certificate is invalid. Try deploying with --debug to troubleshoot."
    return 1
  fi

  _debug "[$_fortigate_func] Operation successful."
  return 0
}

# Function to deploy a base64-encoded certificate to the firewall
_fortigate_deployer() {
  _fortigate_cert_base64=$(_base64 <"$_fortigate_cfullchain" | tr -d '\n')
  _fortigate_key_base64=$(_base64 <"$_fortigate_ckey" | tr -d '\n')
  _fortigate_payload=$(
    cat <<EOF
{
  "type": "regular",
  "scope": "global",
  "certname": "$_fortigate_cert_name",
  "key_file_content": "$_fortigate_key_base64",
  "file_content": "$_fortigate_cert_base64"
}
EOF
  )

  _fortigate_url="https://${FGT_HOST}:${FGT_PORT}/api/v2/monitor/vpn-certificate/local/import"
  _debug "Uploading certificate via URL: $_fortigate_url"

  _H1="Authorization: Bearer $FGT_TOKEN"
  _fortigate_response=$(_post "$_fortigate_payload" "$_fortigate_url" "" "POST" "application/json")
  _debug "FortiGate API Response: $_fortigate_response"

  _fortigate_parse_response "$_fortigate_response" "Deploying certificate" || return 1
}

# Function to upload a CA certificate to the firewall
# FortiGate does not automatically extract the CA from the full chain.
_fortigate_upload_ca_cert() {
  _fortigate_ca_base64=$(_base64 <"$_fortigate_cca" | tr -d '\n')
  _fortigate_payload=$(
    cat <<EOF
{
  "import_method": "file",
  "scope": "global",
  "file_content": "$_fortigate_ca_base64"
}
EOF
  )

  _fortigate_url="https://${FGT_HOST}:${FGT_PORT}/api/v2/monitor/vpn-certificate/ca/import"
  _debug "Uploading CA certificate via URL: $_fortigate_url"

  _H1="Authorization: Bearer $FGT_TOKEN"
  _fortigate_response=$(_post "$_fortigate_payload" "$_fortigate_url" "" "POST" "application/json")
  _debug "FortiGate API CA Response: $_fortigate_response"

  # FortiGate error -328 means that the CA certificate already exists.
  if echo "$_fortigate_response" | grep -q '"error":[ ]*-328'; then
    _debug "CA certificate already exists. Skipping CA upload."
    return 0
  fi

  _fortigate_parse_response "$_fortigate_response" "Deploying CA certificate" || return 1
}

# Function to activate the new certificate
_fortigate_set_active_web_cert() {
  _fortigate_payload=$(
    cat <<EOF
{
  "admin-server-cert": "$_fortigate_cert_name"
}
EOF
  )

  _fortigate_url="https://${FGT_HOST}:${FGT_PORT}/api/v2/cmdb/system/global"
  _debug "Setting GUI certificate..."

  _H1="Authorization: Bearer $FGT_TOKEN"
  _fortigate_response=$(_post "$_fortigate_payload" "$_fortigate_url" "" "PUT" "application/json")

  _fortigate_parse_response "$_fortigate_response" "Assigning active certificate" || return 1
}

# Function to clean up the previously deployed certificate
_fortigate_cleanup_previous_certificate() {
  _getdeployconf FGT_LAST_CERT

  if [ -n "$FGT_LAST_CERT" ] && [ "$FGT_LAST_CERT" != "$_fortigate_cert_name" ]; then
    _debug "Found previously deployed certificate: $FGT_LAST_CERT. Deleting it."

    _fortigate_url="https://${FGT_HOST}:${FGT_PORT}/api/v2/cmdb/vpn.certificate/local/${FGT_LAST_CERT}"
    _H1="Authorization: Bearer $FGT_TOKEN"
    _fortigate_response=$(_post "" "$_fortigate_url" "" "DELETE" "application/json")
    _debug "Delete certificate API response: $_fortigate_response"

    _fortigate_parse_response "$_fortigate_response" "Delete previous certificate" || return 1
  else
    _debug "No previous certificate found."
  fi
}

# Main deploy-hook function
fortigate_deploy() {
  # Include date and time to ensure unique names.
  _fortigate_cert_name="$(echo "$1" | sed 's/*/WILDCARD_/g')_$(date -u +"%Y-%m-%d_%H-%M-%S")"
  _fortigate_ckey="$2"
  _fortigate_cca="$4"
  _fortigate_cfullchain="$5"

  if [ ! -f "$_fortigate_ckey" ] || [ ! -f "$_fortigate_cfullchain" ]; then
    _err "Valid key and/or certificate not found."
    return 1
  fi

  # Save required environment variables if set; otherwise load saved values.
  for _fortigate_var in FGT_HOST FGT_TOKEN FGT_PORT; do
    if [ -n "$(eval echo "\$$_fortigate_var")" ]; then
      _debug "Detected ENV variable $_fortigate_var. Saving to file."
      _savedeployconf "$_fortigate_var" "$(eval echo "\$$_fortigate_var")" 1
    else
      _debug "Attempting to load variable $_fortigate_var from file."
      _getdeployconf "$_fortigate_var"
    fi
  done

  if [ -z "$FGT_HOST" ] || [ -z "$FGT_TOKEN" ]; then
    _err "FGT_HOST and FGT_TOKEN must be set."
    return 1
  fi

  FGT_PORT="${FGT_PORT:-443}"
  _debug "Using FortiGate port: $FGT_PORT"

  # Upload the new certificate.
  _fortigate_deployer || return 1

  # Upload the CA certificate.
  if [ -n "$_fortigate_cca" ] && [ -f "$_fortigate_cca" ]; then
    _fortigate_upload_ca_cert || return 1
  else
    _debug "No CA certificate provided."
  fi

  # Activate the new certificate.
  _fortigate_set_active_web_cert || return 1

  # Delete the previously deployed certificate only after successful activation.
  _fortigate_cleanup_previous_certificate || return 1

  # Save the new certificate name for cleanup during the next deployment.
  _savedeployconf "FGT_LAST_CERT" "$_fortigate_cert_name" 1
}
