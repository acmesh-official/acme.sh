#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_mijnhost_info='mijn.host
Site: mijn.host
Docs: https://github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_mijnhost
Options:
 MIJNHOST_API_KEY API Key
Issues: github.com/acmesh-official/acme.sh/issues/6177
Author: @peterv99
'

########  Public functions ######################
MIJNHOST_API="https://mijn.host/api/v2"

# Add TXT record for domain verification
dns_mijnhost_add() {
  fulldomain=$1
  txtvalue=$2

  MIJNHOST_API_KEY="${MIJNHOST_API_KEY:-$(_readaccountconf_mutable MIJNHOST_API_KEY)}"
  if [ -z "$MIJNHOST_API_KEY" ]; then
    MIJNHOST_API_KEY=""
    _err "You haven't specified your mijn-host API key yet."
    _err "Please add MIJNHOST_API_KEY to the env."
    return 1
  fi

  # Save the API key for future use
  _saveaccountconf_mutable MIJNHOST_API_KEY "$MIJNHOST_API_KEY"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _debug2 _sub_domain "$_sub_domain"
  _debug2 _domain "$_domain"
  _debug "Adding DNS record" "${fulldomain}."

  # Construct the API URL
  api_url="$MIJNHOST_API/domains/$_domain/dns"

  # Getting previous records
  _mijnhost_rest GET "$api_url" ""

  if [ "$_code" != "200" ]; then
    _err "Error getting current DNS enties ($_code)"
    return 1
  fi

  records=$(echo "$response" | _egrep_o '"records":\[.*\]' | sed 's/"records"://')

  _debug2 "Current records" "$records"

  # Build the payload for the API
  data="{\"type\":\"TXT\",\"name\":\"$fulldomain.\",\"value\":\"$txtvalue\",\"ttl\":300}"

  _debug2 "Record to add" "$data"

  # Updating the records
  updated_records=$(echo "$records" | sed -E "s/\]( *$)/,$data\]/")

  _debug2 "Updated records" "$updated_records"

  # data
  data="{\"records\": $updated_records}"

  _mijnhost_rest PUT "$api_url" "$data"

  if [ "$_code" = "200" ]; then
    _info "DNS record succesfully added."
    return 0
  else
    _err "Error adding DNS record ($_code)."
    return 1
  fi
}

# Remove TXT record after verification
dns_mijnhost_rm() {
  fulldomain=$1
  txtvalue=$2

  MIJNHOST_API_KEY="${MIJNHOST_API_KEY:-$(_readaccountconf_mutable MIJNHOST_API_KEY)}"
  if [ -z "$MIJNHOST_API_KEY" ]; then
    MIJNHOST_API_KEY=""
    _err "You haven't specified your mijn-host API key yet."
    _err "Please add MIJNHOST_API_KEY to the env."
    return 1
  fi

  _debug "Detecting root zone for" "${fulldomain}."
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _debug "Removing DNS record for TXT value" "${txtvalue}."

  # Construct the API URL
  api_url="$MIJNHOST_API/domains/$_domain/dns"

  # Get current records
  _mijnhost_rest GET "$api_url" ""

  if [ "$_code" != "200" ]; then
    _err "Error getting current DNS enties ($_code)"
    return 1
  fi

  _debug2 "Get current records response:" "$response"

  records=$(echo "$response" | _egrep_o '"records":\[.*\]' | sed 's/"records"://')

  _debug2 "Current records:" "$records"

  updated_records=$(echo "$records" | sed -E "s/\{[^}]*\"value\":\"$txtvalue\"[^}]*\},?//g" | sed 's/,]/]/g')

  _debug2 "Updated records:" "$updated_records"

  # Build the new payload
  data="{\"records\": $updated_records}"

  # Use the _put method to update the records
  _mijnhost_rest PUT "$api_url" "$data"

  if [ "$_code" = "200" ]; then
    _info "DNS record removed successfully."
    return 0
  else
    _err "Error removing DNS record ($_code)."
    return 1
  fi
}

# Helper function to detect the root zone
_get_root() {
  domain=$1

  # Get current records
  _debug "Getting current domains"
  _mijnhost_rest GET "$MIJNHOST_API/domains" ""

  if [ "$_code" != "200" ]; then
    _err "error getting current domains ($_code)"
    return 1
  fi

  # Extract root domains from response
  rootDomains=$(echo "$response" | _egrep_o '"domain":"[^"]*"' | sed -E 's/"domain":"([^"]*)"/\1/')
  _debug "Root domains:" "$rootDomains"

  for rootDomain in $rootDomains; do
    if _contains "$domain" "$rootDomain"; then
      _domain="$rootDomain"
      _sub_domain=$(echo "$domain" | sed "s/.$rootDomain//g")
      _debug "Found root domain" "$_domain" "and subdomain" "$_sub_domain" "for" "$domain"
      return 0
    fi
  done
  return 1
}

# Helper function for rest calls
_mijnhost_rest() {
  m=$1
  ep="$2"
  data="$3"

  MAX_REQUEST_RETRY_TIMES=15
  _request_retry_times=0
  _retry_sleep=5 #Initial sleep time in seconds.

  while [ "${_request_retry_times}" -lt "$MAX_REQUEST_RETRY_TIMES" ]; do
    _debug2 _request_retry_times "$_request_retry_times"
    export _H1="API-Key: $MIJNHOST_API_KEY"
    export _H2="Content-Type: application/json"
    # clear headers from previous request to avoid getting wrong http code on timeouts
    : >"$HTTP_HEADER"
    _debug "$ep"
    if [ "$m" != "GET" ]; then
      _debug2 "data $data"
      response="$(_post "$data" "$ep" "" "$m")"
    else
      response="$(_get "$ep")"
    fi
    _ret="$?"
    _debug2 "response $response"
    _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
    _debug "http response code $_code"
    if [ "$_code" = "401" ]; then
      # we have an invalid API token, maybe it is expired?
      _err "Access denied. Invalid API token."
      return 1
    fi

    if [ "$_ret" != "0" ] || [ -z "$_code" ] || [ "$_code" = "400" ] || _contains "$response" "DNS records not managed by mijn.host"; then #Sometimes API errors out
      _request_retry_times="$(_math "$_request_retry_times" + 1)"
      _info "REST call error $_code retrying $ep in ${_retry_sleep}s"
      _sleep "$_retry_sleep"
      _retry_sleep="$(_math "$_retry_sleep" \* 2)"
      continue
    fi
    break
  done
  if [ "$_request_retry_times" = "$MAX_REQUEST_RETRY_TIMES" ]; then
    _err "Error mijn.host API call was retried $MAX_REQUEST_RETRY_TIMES times."
    _err "Calling $ep failed."
    return 1
  fi
  response="$(echo "$response" | _normalizeJson)"
  return 0
}
