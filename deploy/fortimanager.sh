#!/usr/bin/env sh
# Script to deploy a certificate to FortiManager via API and set it as the current web GUI certificate.
# FortiManager has character limit of 35 characters for certificate names.
# Upon succesful activation of certificate FortiManager directly restarts webserver, the deploy hook
# sleeps for 5 seconds after that so that it can recover.
#
# REQUIRED:
#     export FMG_HOST="fortimanager_hostname-or-ip"
#     export FMG_TOKEN="fortimanager_api_token"
#
# OPTIONAL:
#     export FMG_PORT="10443"             # Custom HTTPS port (defaults to 443 if not set)
#
# Run `acme.sh --deploy -d example.com --deploy-hook fortimanager --insecure` to use this script.
# `--insecure` is required on first run if not already using a valid SSL certificate on firewall.

# Function to parse a FortiGate API response
_fortimanager_parse_response() {
  _fortimanager_response="$1"
  _fortimanager_func="$2"
  _fortimanager_status=$(echo "$_fortimanager_response" | _egrep_o '"message":[ ]*"[^"]*"' | cut -d '"' -f 4)
  if [ "$_fortimanager_status" != "OK" ]; then
    return 1
  fi

  _debug "[$_fortimanager_func] Operation successful."
  return 0
}

# Function to deploy a base64-encoded certificate to the FortiManager
_fortimanager_deployer() {
  _fortimanager_ccert_data=$(cat "$_fortimanager_ccert")
  _fortimanager_ckey_data=$(cat "$_fortimanager_ckey")  

  _fortimanager_payload=$(
    cat <<EOF
{
  "method": "add",
  "params": [
    {
      "url": "/cli/global/system/certificate/local",
      "data": {
        "name": "$_fortimanager_cert_name",
        "certificate": ["$_fortimanager_ccert_data"],
        "private-key": "$_fortimanager_ckey_data"
      }
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

  # FortiManager error -2 means that the certificate already exists.
  if echo "$_fortimanager_response" | grep -q '"code":[ ]*-2'; then
    _debug "Certificate already exists. Skipping certificate upload."
    return 0
  fi

  _fortimanager_parse_response "$_fortimanager_response" "Deploying certificate" || return 1
}

# Function to upload a CA certificate to the firewall
_fortimanager_upload_ca_cert() {
  _fortimanager_ca=$(cat "$_fortimanager_cca")
  _fortimanager_ca_name=$(openssl x509 -in "$_fortimanager_cca" -noout -subject -nameopt multiline \
  | awk -F'= ' '/commonName/ {print $2}')

  if [ ${#_fortimanager_ca_name} -gt 35 ]; then
    _err "CA name too long"
    return 1
  fi

  _fortimanager_payload=$(
    cat <<EOF
{
  "method": "add",
  "params": [
    {
      "data": [
        {
          "ca": [
            "$_fortimanager_ca"
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

  # FortiManager error -2 means that the CA certificate already exists.
  if echo "$_fortimanager_response" | grep -q '"code":[ ]*-2'; then
    _debug "CA certificate already exists. Skipping CA upload."
    return 0
  fi

  _fortimanager_parse_response "$_fortimanager_response" "Deploying CA certificate" || return 1
}

# Function to get currently active certificate
_fortimanager_get_active_web_cert() {
  _fortimanager_payload=$(
    cat <<EOF
{
  "method": "get",
  "params": [
    {
      "url": "/cli/global/system/admin/setting"
    }
  ]
}
EOF
  )

  _fortimanager_url="https://${FMG_HOST}:${FMG_PORT}/jsonrpc"
  _debug "Getting current GUI certificate..."

  _H1="Authorization: Bearer $FMG_TOKEN"
  _fortimanager_response=$(_post "$_fortimanager_payload" "$_fortimanager_url" "" "POST" "application/json")

  _fortimanager_current_active_cert=$(echo "$_fortimanager_response" | _egrep_o '"admin_server_cert":[ ]*"[^"]*"' | cut -d '"' -f 4)
}

# Function to activate the new certificate
_fortimanager_set_active_web_cert() {
  # Get current active web cert to check if we can skip this
  _fortimanager_get_active_web_cert

  if [ "$_fortimanager_current_active_cert" = "$_fortimanager_cert_name" ]; then
    _debug "Skipping activating certificate as it is already active"
    return 0
  fi

  _fortimanager_payload=$(
    cat <<EOF
{
  "method": "set",
  "params": [
    {
      "data": {
        "admin_server_cert": "$_fortimanager_cert_name"
      },
      "url": "/cli/global/system/admin/setting"
    }
  ]
}
EOF
  )

  _fortimanager_url="https://${FMG_HOST}:${FMG_PORT}/jsonrpc"
  _debug "Setting GUI certificate..."

  _H1="Authorization: Bearer $FMG_TOKEN"
  _fortimanager_response=$(_post "$_fortimanager_payload" "$_fortimanager_url" "" "PUT" "application/json" 2>/dev/null)
  _post_exit_code=$?

  if [ -n "$_fortimanager_response" ]; then
    if _contains "$_fortimanager_response" '"code":[ ]*0'; then
      _debug "Certificate accepted (webserver will restart)"
    else
      _err "FortiManager rejected the certificate update"
      _debug "$_fortimanager_response"
      return 1
    fi
    else
      _debug "No response body received — assuming webserver restarted after accepting certificate"
    fi

    # wait for webserver to restart
    sleep 5
    return 0
}

# Function to clean up the previously deployed certificate
_fortimanager_cleanup_previous_certificate() {
  _getdeployconf FMG_LAST_CERT

  if [ -n "$FMG_LAST_CERT" ] && [ "$FMG_LAST_CERT" != "$_fortimanager_cert_name" ]; then
    _debug "Found previously deployed certificate: $FMG_LAST_CERT. Deleting it."
    _fortimanager_payload=$(
      cat <<EOF
      {
        "method": "delete",
        "params": [
        {
          "url": "/cli/global/system/certificate/local/$FMG_LAST_CERT"
        }]
      }
EOF
    )

    _fortimanager_url="https://${FMG_HOST}:${FMG_PORT}/jsonrpc"
    _debug "Deleting certificate via URL: $_fortimanager_url"

    _H1="Authorization: Bearer $FMG_TOKEN"
    _fortimanager_response=$(_post "$_fortimanager_payload" "$_fortimanager_url" "" "POST" "application/json")
    _debug "FortiManager API Response: $_fortimanager_response"

      # FortiManager error -3 means that the object does not exist anymore
    if echo "$_fortimanager_response" | grep -q '"code":[ ]*-3'; then
      _debug "Certificate does not exist anymore"
      return 0
    fi

    _fortimanager_parse_response "$_fortimanager_response" "Deleting previous certificate" || return 1
  else
    _debug "No previous certificate found."
  fi
}

fortimanager_deploy() {
  # Replace . in cert name for - and truncate name to 28 characters for date
  _fortimanager_cert_name="$(echo "$1" | tr . - | sed 's/*/WC_/g')"
  _fortimanager_cert_name=$(printf '%.28s' "$_fortimanager_cert_name")
  _fortimanager_ckey="$2"
  _fortimanager_cca="$4"
  _fortimanager_ccert="$3"

  # Get start date and append to name
  _cert_date=$(LC_ALL=C openssl x509 -in "$_fortimanager_ccert" -noout -startdate | cut -d= -f2 \
  | awk 'BEGIN{
      m["Jan"]=1;m["Feb"]=2;m["Mar"]=3;m["Apr"]=4;m["May"]=5;m["Jun"]=6;
      m["Jul"]=7;m["Aug"]=8;m["Sep"]=9;m["Oct"]=10;m["Nov"]=11;m["Dec"]=12
    } {printf "%02d%02d%02d", substr($4,3), m[$1], $2}')
  _fortimanager_cert_name="${_fortimanager_cert_name}_${_cert_date}"

  if [ ! -f "$_fortimanager_ckey" ] || [ ! -f "$_fortimanager_ccert" ]; then
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

  # Upload the new certificate.
  _fortimanager_deployer || return 1

  # Upload the CA certificate.
  if [ -n "$_fortimanager_cca" ] && [ -f "$_fortimanager_cca" ]; then
    _fortimanager_upload_ca_cert || return 1
  else
    _debug "No CA certificate provided."
  fi

  # Activate the new certificate.
  _fortimanager_set_active_web_cert || return 1

  # Delete the previously deployed certificate only after successful activation.
  _fortimanager_cleanup_previous_certificate || return 1

  # Save the new certificate name for cleanup during the next deployment.
  _savedeployconf "FMG_LAST_CERT" "$_fortimanager_cert_name" 1
}