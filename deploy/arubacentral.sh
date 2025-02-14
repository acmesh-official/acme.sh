#!/usr/bin/env sh
# Aruba Central deploy hook for acme.sh

arubacentral_deploy() {
  # Generate unique certificate name with a proper random number (5 digits)
  _cdomain="$(echo "$1" | sed 's/*/WILDCARD_/g')_$(tr -dc '0-9' </dev/urandom | head -c 5)"
  _ckey="$2"
  _cca="$4"
  _cfullchain="$5"
  _cpfx="${_cfullchain%.cer}.pfx"
  _passphrase="central123"

  _debug "Generated certificate name: $_cdomain"

  # Check required files
  if [ ! -f "$_ckey" ] || [ ! -f "$_cfullchain" ]; then
    _err "Valid key and/or certificate not found."
    return 1
  fi

  # Load API credentials
  for var in ARUBA_HOST ARUBA_CLIENT_ID ARUBA_CLIENT_SECRET ARUBA_REFRESH_TOKEN; do
    if [ "$(eval echo \$$var)" ]; then
      _debug "Detected ENV variable $var. Saving to file."
      _savedeployconf "$var" "$(eval echo \$$var)" 1
    else
      _debug "Attempting to load variable $var from file."
      _getdeployconf "$var"
    fi
  done

  if [ -z "$ARUBA_HOST" ] || [ -z "$ARUBA_CLIENT_ID" ] || [ -z "$ARUBA_CLIENT_SECRET" ] || [ -z "$ARUBA_REFRESH_TOKEN" ]; then
    _err "ARUBA_HOST, ARUBA_CLIENT_ID, ARUBA_CLIENT_SECRET, and ARUBA_REFRESH_TOKEN must be set."
    return 1
  fi

  # Refresh Access Token Only If Needed (Handled in upload function)
  _refresh_access_token || return 1

  # Delete old certificate before deploying a new one
  _delete_old_certificate

  # Convert certificate to PKCS12 using built-in `_toPkcs()`
  _debug "Converting certificate to PKCS12 format using _toPkcs()..."
  _toPkcs "$_cpfx" "$_ckey" "$_cfullchain" "$_cca" "$_passphrase" "$_cdomain"
  if [ $? -ne 0 ]; then
    _err "Failed to convert certificate to PKCS12."
    return 1
  fi

  # Base64 encode the PFX certificate
  _debug "Encoding PKCS12 certificate in Base64..."
  _pfx_base64=$(_base64 <"$_cpfx" | tr -d '\n')

  # Base64 encode the passphrase
  _debug "Encoding passphrase in Base64..."
  _passphrase_base64=$(printf "%s" "$_passphrase" | _base64 | tr -d '\n')

  # Upload Certificate with Automatic Token Refresh on Failure
  _upload_certificate || return 1
}

# Function to upload the certificate and retry if token is invalid
_upload_certificate() {
  # Prepare JSON payload
  _debug "Preparing JSON payload..."
  payload=$(
    cat <<EOF
{
  "cert_name": "$_cdomain",
  "cert_type": "SERVER_CERT",
  "cert_format": "PKCS12",
  "passphrase": "$_passphrase_base64",
  "cert_data": "$_pfx_base64"
}
EOF
  )

  # Upload URL
  url="${ARUBA_HOST}/configuration/v1/certificates"
  _debug "Uploading certificate to Aruba Central: $url"

  # Set Authorization Header
  _H1="Authorization: Bearer $ARUBA_ACCESS_TOKEN"

  # Attempt to upload the certificate
  response=$(_post "$payload" "$url" "" "POST" "application/json")
  _debug "Aruba Central API Response: $response"

  # If the token is invalid, refresh it and retry once
  if echo "$response" | grep -q '"error":"invalid_token"'; then
    _debug "❌ Access token is invalid. Refreshing and retrying..."
    if _refresh_access_token; then
      _H1="Authorization: Bearer $ARUBA_ACCESS_TOKEN"
      response=$(_post "$payload" "$url" "" "POST" "application/json")
      _debug "Retry API Response: $response"
    else
      _err "❌ Token refresh failed. Cannot upload certificate."
      return 1
    fi
  fi

  # Check if upload was successful
  if echo "$response" | grep -q '"cert_md5_checksum"'; then
    _debug "✅ Certificate uploaded successfully!"
    _savedeployconf "ARUBA_LAST_CERT" "$_cdomain" 1
    return 0
  else
    _err "❌ Failed to upload certificate. Deploy with --debug to troubleshoot."
    return 1
  fi
}

# Function to refresh API token only if expired
_refresh_access_token() {
  _getdeployconf "ARUBA_ACCESS_TOKEN"
  _getdeployconf "ARUBA_REFRESH_TOKEN"

  # 🔍 Step 1: Check if the access token is still valid
  _debug "Checking if the access token is still valid..."
  check_url="${ARUBA_HOST}/configuration/v1/certificates?limit=1"
  _H1="Authorization: Bearer $ARUBA_ACCESS_TOKEN"
  response=$(_post "" "$check_url" "" "GET" "application/json")

  if echo "$response" | grep -q '"error":"invalid_token"'; then
    _debug "❌ Access token is invalid, refreshing..."
  else
    _debug "✅ Access token is still valid, skipping refresh."
    return 0 # Skip refresh
  fi

  # 🔄 Step 2: Refresh token if it's invalid
  _debug "Refreshing Aruba Central API token..."
  refresh_url="${ARUBA_HOST}/oauth2/token"

  payload=$(
    cat <<EOF
{
  "client_id": "$ARUBA_CLIENT_ID",
  "client_secret": "$ARUBA_CLIENT_SECRET",
  "grant_type": "refresh_token",
  "refresh_token": "$ARUBA_REFRESH_TOKEN"
}
EOF
  )

  response=$(_post "$payload" "$refresh_url" "" "POST" "application/json")
  _debug "Token Refresh Response: $response"

  new_token=$(echo "$response" | grep -o '"access_token":[ ]*"[^"]*"' | sed 's/"access_token":[ ]*"\([^"]*\)"/\1/')
  new_refresh_token=$(echo "$response" | grep -o '"refresh_token":[ ]*"[^"]*"' | sed 's/"refresh_token":[ ]*"\([^"]*\)"/\1/')

  if [ -n "$new_token" ]; then
    _debug "✅ Token refreshed successfully!"
    _savedeployconf "ARUBA_ACCESS_TOKEN" "$new_token" 1
    ARUBA_ACCESS_TOKEN="$new_token"

    if [ -n "$new_refresh_token" ]; then
      _debug "🔄 Updating refresh token..."
      _savedeployconf "ARUBA_REFRESH_TOKEN" "$new_refresh_token" 1
      ARUBA_REFRESH_TOKEN="$new_refresh_token"
    else
      _debug "⚠️ Aruba Central did not return a new refresh token! Keeping the old one."
    fi
  else
    _err "❌ Failed to refresh API token. Please manually generate a new one."
    return 1
  fi
}

# Function to delete the previous certificate
_delete_old_certificate() {
  _getdeployconf "ARUBA_LAST_CERT"

  if [ -n "$ARUBA_LAST_CERT" ]; then
    _debug "Found previous certificate: $ARUBA_LAST_CERT. Deleting it..."
    delete_url="${ARUBA_HOST}/configuration/v1/certificates/${ARUBA_LAST_CERT}"
    _H1="Authorization: Bearer $ARUBA_ACCESS_TOKEN"

    response=$(_post "" "$delete_url" "" "DELETE" "application/json")
    _debug "Delete certificate API response: $response"

    if echo "$response" | grep -q '"error"'; then
      _err "❌ Failed to delete previous certificate."
    else
      _debug "✅ Previous certificate deleted successfully."
    fi
  else
    _debug "No previous certificate found. Skipping deletion."
  fi
}
