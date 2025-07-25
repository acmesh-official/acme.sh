#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_spaceship_info='Spaceship.com
Site: Spaceship.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_spaceship
Options:
 SPACESHIP_API_KEY API Key
 SPACESHIP_API_SECRET API Secret
 SPACESHIP_ROOT_DOMAIN Root domain. Manually specify the root domain if auto-detection fails. Optional.
Issues: github.com/acmesh-official/acme.sh/issues/6304
Author: Meow <@Meo597>
'

# Spaceship API
# https://docs.spaceship.dev/

########  Public functions #####################

SPACESHIP_API_BASE="https://spaceship.dev/api/v1"

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_spaceship_add() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Adding TXT record for $fulldomain with value $txtvalue"

  # Initialize API credentials and headers
  if ! _spaceship_init; then
    return 1
  fi

  # Detect root zone
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  # Extract subdomain part relative to root domain
  subdomain=$(echo "$fulldomain" | sed "s/\.$_domain$//")
  if [ "$subdomain" = "$fulldomain" ]; then
    _err "Failed to extract subdomain from $fulldomain relative to root domain $_domain"
    return 1
  fi
  _debug "Extracted subdomain: $subdomain for root domain: $_domain"

  # Escape txtvalue to prevent JSON injection (e.g., quotes in txtvalue)
  escaped_txtvalue=$(echo "$txtvalue" | sed 's/"/\\"/g')

  # Prepare payload and URL for adding TXT record
  # Note: 'name' in payload uses subdomain (e.g., _acme-challenge.sub) as required by Spaceship API
  payload="{\"force\": true, \"items\": [{\"type\": \"TXT\", \"name\": \"$subdomain\", \"value\": \"$escaped_txtvalue\", \"ttl\": 600}]}"
  url="$SPACESHIP_API_BASE/dns/records/$_domain"

  # Send API request
  if _spaceship_api_request "PUT" "$url" "$payload"; then
    _info "Successfully added TXT record for $fulldomain"
    return 0
  else
    _err "Failed to add TXT record. If the domain $_domain is incorrect, set SPACESHIP_ROOT_DOMAIN to the correct root domain."
    return 1
  fi
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_spaceship_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Removing TXT record for $fulldomain with value $txtvalue"

  # Initialize API credentials and headers
  if ! _spaceship_init; then
    return 1
  fi

  # Detect root zone
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  # Extract subdomain part relative to root domain
  subdomain=$(echo "$fulldomain" | sed "s/\.$_domain$//")
  if [ "$subdomain" = "$fulldomain" ]; then
    _err "Failed to extract subdomain from $fulldomain relative to root domain $_domain"
    return 1
  fi
  _debug "Extracted subdomain: $subdomain for root domain: $_domain"

  # Escape txtvalue to prevent JSON injection
  escaped_txtvalue=$(echo "$txtvalue" | sed 's/"/\\"/g')

  # Prepare payload and URL for deleting TXT record
  # Note: 'name' in payload uses subdomain (e.g., _acme-challenge.sub) as required by Spaceship API
  payload="[{\"type\": \"TXT\", \"name\": \"$subdomain\", \"value\": \"$escaped_txtvalue\"}]"
  url="$SPACESHIP_API_BASE/dns/records/$_domain"

  # Send API request
  if _spaceship_api_request "DELETE" "$url" "$payload"; then
    _info "Successfully deleted TXT record for $fulldomain"
    return 0
  else
    _err "Failed to delete TXT record. If the domain $_domain is incorrect, set SPACESHIP_ROOT_DOMAIN to the correct root domain."
    return 1
  fi
}

####################  Private functions below ##################################

_spaceship_init() {
  SPACESHIP_API_KEY="${SPACESHIP_API_KEY:-$(_readaccountconf_mutable SPACESHIP_API_KEY)}"
  SPACESHIP_API_SECRET="${SPACESHIP_API_SECRET:-$(_readaccountconf_mutable SPACESHIP_API_SECRET)}"

  if [ -z "$SPACESHIP_API_KEY" ] || [ -z "$SPACESHIP_API_SECRET" ]; then
    _err "Spaceship API credentials are not set. Please set SPACESHIP_API_KEY and SPACESHIP_API_SECRET."
    _err "Ensure \"$LE_CONFIG_HOME\" directory has restricted permissions (chmod 700 \"$LE_CONFIG_HOME\") to protect credentials."
    return 1
  fi

  # Save credentials to account config for future renewals
  _saveaccountconf_mutable SPACESHIP_API_KEY "$SPACESHIP_API_KEY"
  _saveaccountconf_mutable SPACESHIP_API_SECRET "$SPACESHIP_API_SECRET"

  # Set common headers for API requests
  export _H1="X-API-Key: $SPACESHIP_API_KEY"
  export _H2="X-API-Secret: $SPACESHIP_API_SECRET"
  export _H3="Content-Type: application/json"
  return 0
}

_get_root() {
  domain="$1"

  # Check manual override
  SPACESHIP_ROOT_DOMAIN="${SPACESHIP_ROOT_DOMAIN:-$(_readdomainconf SPACESHIP_ROOT_DOMAIN)}"
  if [ -n "$SPACESHIP_ROOT_DOMAIN" ]; then
    _domain="$SPACESHIP_ROOT_DOMAIN"
    _debug "Using manually specified or saved root domain: $_domain"
    _savedomainconf SPACESHIP_ROOT_DOMAIN "$SPACESHIP_ROOT_DOMAIN"
    return 0
  fi

  _debug "Detecting root zone for '$domain'"

  i=1
  p=1
  while true; do
    _cutdomain=$(printf "%s" "$domain" | cut -d . -f "$i"-100)

    _debug "Attempt i=$i: Checking if '$_cutdomain' is root zone (cut ret=$?)"

    if [ -z "$_cutdomain" ]; then
      _debug "Cut resulted in empty string, root zone not found."
      break
    fi

    # Call the API to check if this _cutdomain is a manageable zone
    if _spaceship_api_request "GET" "$SPACESHIP_API_BASE/dns/records/$_cutdomain?take=1&skip=0"; then
      # API call succeeded (HTTP 200 OK for GET /dns/records)
      _domain="$_cutdomain"
      _debug "Root zone found: '$_domain'"

      # Save the detected root domain
      _savedomainconf SPACESHIP_ROOT_DOMAIN "$_domain"
      _info "Root domain '$_domain' saved to configuration for future use."

      return 0
    fi

    _debug "API check failed for '$_cutdomain'. Continuing search."

    p=$i
    i=$((i + 1))
  done

  _err "Could not detect root zone for '$domain'. Please set SPACESHIP_ROOT_DOMAIN manually."
  return 1
}

_spaceship_api_request() {
  method="$1"
  url="$2"
  payload="$3"

  _debug2 "Sending $method request to $url with payload $payload"
  if [ "$method" = "GET" ]; then
    response="$(_get "$url")"
  else
    response="$(_post "$payload" "$url" "" "$method")"
  fi

  if [ "$?" != "0" ]; then
    _err "API request failed. Response: $response"
    return 1
  fi

  _debug2 "API response body: $response"

  if [ "$method" = "GET" ]; then
    if _contains "$(_head_n 1 <"$HTTP_HEADER")" '200'; then
      return 0
    fi
  else
    if _contains "$(_head_n 1 <"$HTTP_HEADER")" '204'; then
      return 0
    fi
  fi

  _debug2 "API response header: $HTTP_HEADER"
  return 1
}
