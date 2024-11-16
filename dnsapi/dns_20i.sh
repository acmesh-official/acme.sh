#!/bin/bash

# Helper function: Perform a GET request
_get() {
  local url=$1
  local Bearer=$2
  curl -s -H "Authorization: Bearer $Bearer" "$url"
}

# Helper function: Perform a POST request
_post() {
  local data=$1
  local url=$2
  local Bearer=$3
  curl -s -X POST -H "Authorization: Bearer $Bearer" -H "Content-Type: application/json" -d "$data" "$url"
}


# Helper function to parse arguments
_parse_arguments() {
  for arg in "$@"; do
    case "$arg" in
      --bearer=*)
        _bearer="${arg#*=}"
        ;;
      --debug)
        debug=true
        ;;
    esac
  done
}

# Add a TXT record to 20i DNS
dns_20i_add() {
  local fulldomain=$1
  local txtvalue=$2

  # Parse arguments for bearer token or other credentials
  _parse_arguments "$@"

  # Use the passed bearer token or fallback to environment variable
  local bearer="${_bearer:-$U20I_Bearer}"

  if [ -z "$bearer" ]; then
    echo "Error: Bearer token must be provided using --bearer or U20I_Bearer environment variable."
    return 1
  fi

  echo "Adding TXT record to 20i for domain: $fulldomain"

  # Extract root domain and subdomain
  local domain=$(echo "$fulldomain" | sed -r 's/^[^\.]+\.(.+)$/\1/')
  local subdomain="_acme-challenge"

  # Check if the TXT record already exists
  local dns_response=$(_get "https://api.20i.com/domain/$domain/dns" $bearer)
  if echo "$dns_response" | jq -e '.error' > /dev/null 2>&1; then
    local error_message=$(echo "$dns_response" | jq -r '.error.message')
    echo "Error retrieving DNS records: $error_message"
    return 1
  fi

  if echo "$dns_response" | jq -e ".records[] | select(.type == \"TXT\" and .host == \"$fulldomain\" and .txt == \"$txtvalue\")" > /dev/null 2>&1; then
    echo "TXT record already exists. Skipping addition."
    return 0
  fi

  # Construct payload for adding the TXT record
  local payload=$(cat <<EOF
{
  "new": {
    "TXT": [
      {
        "host": "$subdomain",
        "txt": "$txtvalue"
      }
    ]
  }
}
EOF
  )

  # Make API request to add the TXT record
  local add_response=$(_post "$payload" "https://api.20i.com/domain/$domain/dns" $bearer)
  if echo "$add_response" | jq -e '.error' > /dev/null 2>&1; then
    local error_message=$(echo "$add_response" | jq -r '.error.message')
    echo "Error adding TXT record: $error_message"
    return 1
  fi

  echo "TXT record added successfully."
  return 0
}

# Remove a TXT record from 20i DNS
dns_20i_rm() {
  local fulldomain=$1
  local txtvalue=$2

    # Parse arguments for bearer token or other credentials
  _parse_arguments "$@"

  # Use the passed bearer token or fallback to environment variable
  local bearer="${_bearer:-$U20I_Bearer}"

  if [ -z "$bearer" ]; then
    echo "Error: Bearer token must be provided using --bearer or U20I_Bearer environment variable."
    return 1
  fi

  echo "Removing TXT record from 20i for domain: $fulldomain"

  # Extract root domain and subdomain
  local domain=$(echo "$fulldomain" | sed -r 's/^[^\.]+\.(.+)$/\1/')

  # Get existing DNS records
  local dns_response=$(_get "https://api.20i.com/domain/$domain/dns" $bearer)
  if echo "$dns_response" | jq -e '.error' > /dev/null 2>&1; then
    local error_message=$(echo "$dns_response" | jq -r '.error.message')
    echo "Error retrieving DNS records: $error_message"
    return 1
  fi

  # Find the record to delete by matching TXT record
  local record_ref=$(echo "$dns_response" | jq -r \
    ".records[] | select(.type == \"TXT\" and .host == \"$fulldomain\" and .txt == \"$txtvalue\") | .ref")

  if [ -z "$record_ref" ] || [ "$record_ref" == "null" ]; then
    echo "No matching TXT record found for removal."
    return 1
  fi

  # Construct payload for deleting the TXT record
  local payload=$(cat <<EOF
{
  "delete": [
    "$record_ref"
  ],
  "conflictPolicy": "replace"
}
EOF
  )

  # Make API request to remove the TXT record
  local remove_response=$(_post "$payload" "https://api.20i.com/domain/$domain/dns" $bearer)
  if echo "$remove_response" | jq -e '.error' > /dev/null 2>&1; then
    local error_message=$(echo "$remove_response" | jq -r '.error.message')
    echo "Error removing TXT record: $error_message"
    return 1
  fi

  echo "TXT record removed successfully."
  return 0
}
