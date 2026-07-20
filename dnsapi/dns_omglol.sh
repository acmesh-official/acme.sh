#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_omglol_info='omg.lol
Site: omg.lol
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_omglol
Options:
 OMG_ApiKey - API Key. This is accessible from the bottom of the account page at https://home.omg.lol/account
 OMG_Address - Address. This is your omg.lol address, without the preceding @ - you can see your list on your dashboard at https://home.omg.lol/dashboard
Issues: github.com/acmesh-official/acme.sh/issues/5299
Author: @Kholin <kholin+acme.omglolapi@omg.lol>
'

# See API Docs https://api.omg.lol/

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_omglol_add() {
  fulldomain=$1
  txtvalue=$2
  OMG_ApiKey="${OMG_ApiKey:-$(_readaccountconf_mutable OMG_ApiKey)}"
  OMG_Address="${OMG_Address:-$(_readaccountconf_mutable OMG_Address)}"

  # As omg.lol includes a leading @ for their addresses, pre-strip this before save
  OMG_Address="$(echo "$OMG_Address" | tr -d '@')"

  _saveaccountconf_mutable OMG_ApiKey "$OMG_ApiKey"
  _saveaccountconf_mutable OMG_Address "$OMG_Address"

  _info "Using omg.lol."
  _debug "Function" "dns_omglol_add()"
  _debug "Full Domain Name" "$fulldomain"
  _debug "txt Record Value" "$txtvalue"
  _secure_debug "omg.lol API key" "$OMG_ApiKey"
  _debug "omg.lol Address" "$OMG_Address"

  omg_validate "$OMG_ApiKey" "$OMG_Address" "$fulldomain"
  if [ 1 = $? ]; then
    return 1
  fi

  dnsName=$(_getDnsRecordName "$fulldomain" "$OMG_Address")
  authHeader="$(_createAuthHeader "$OMG_ApiKey")"

  _debug2 "dns_omglol_add(): Address" "$dnsName"

  omg_add "$OMG_Address" "$authHeader" "$dnsName" "$txtvalue"

}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_omglol_rm() {
  fulldomain=$1
  txtvalue=$2
  OMG_ApiKey="${OMG_ApiKey:-$(_readaccountconf_mutable OMG_ApiKey)}"
  OMG_Address="${OMG_Address:-$(_readaccountconf_mutable OMG_Address)}"

  # As omg.lol includes a leading @ for their addresses, strip this in case provided
  OMG_Address="$(echo "$OMG_Address" | tr -d '@')"

  _info "Using omg.lol"
  _debug "Function" "dns_omglol_rm()"
  _debug "Full Domain Name" "$fulldomain"
  _debug "txt Record Value" "$txtvalue"
  _secure_debug "omg.lol API key" "$OMG_ApiKey"
  _debug "omg.lol Address" "$OMG_Address"

  omg_validate "$OMG_ApiKey" "$OMG_Address" "$fulldomain"
  if [ 1 = $? ]; then
    return 1
  fi

  dnsName=$(_getDnsRecordName "$fulldomain" "$OMG_Address")
  authHeader="$(_createAuthHeader "$OMG_ApiKey")"

  omg_delete "$OMG_Address" "$authHeader" "$dnsName" "$txtvalue"
}

####################  Private functions below ##################################
# Check that the minimum requirements are present.  Close ungracefully if not
omg_validate() {
  omg_apikey=$1
  omg_address=$2
  fulldomain=$3

  _debug2 "Function" "dns_validate()"
  _secure_debug2 "omg.lol API key" "$omg_apikey"
  _debug2 "omg.lol Address" "$omg_address"
  _debug2 "Full Domain Name" "$fulldomain"

  if [ "" = "$omg_address" ]; then
    _err "omg.lol base address not provided.  Exiting"
    return 1
  fi

  if [ "" = "$omg_apikey" ]; then
    _err "omg.lol API key not provided.  Exiting"
    return 1
  fi

  _endswith "$fulldomain" "omg.lol"
  if [ 1 = $? ]; then
    _err "Domain name requested is not under omg.lol"
    return 1
  fi

  _endswith "$fulldomain" "$omg_address.omg.lol"
  if [ 1 = $? ]; then
    _err "Domain name is not a subdomain of provided omg.lol address $omg_address"
    return 1
  fi

  omg_testconnect "$omg_apikey" "$omg_address"
  if [ 1 = $? ]; then
    _err "Authentication to omg.lol for address $omg_address using provided API key failed"
    return 1
  fi

  _debug "Required environment parameters are all present and validated"
}

# Validate that the address and API key are both correct and associated to each other
omg_testconnect() {
  omg_apikey=$1
  omg_address=$2

  _debug2 "Function" "omg_testconnect"
  _secure_debug2 "omg.lol API key" "$omg_apikey"
  _debug2 "omg.lol Address" "$omg_address"

  authheader="$(_createAuthHeader "$omg_apikey")"
  export _H1="$authheader"
  endpoint="https://api.omg.lol/address/$omg_address/info"
  _debug2 "Endpoint for validation" "$endpoint"

  response=$(_get "$endpoint" "" 30)

  _jsonResponseCheck "$response" "status_code" 200
  if [ 1 = $? ]; then
    _debug2 "Failed to query omg.lol for $omg_address with provided API key"
    _secure_debug2 "API Key" "omg_apikey"
    _secure_debug3 "Raw response" "$response"
    return 1
  fi
}

# Add (or modify) an entry for a new ACME query
omg_add() {
  address=$1
  authHeader=$2
  dnsName=$3
  txtvalue=$4

  _info "Creating DNS entry for $dnsName"
  _debug2 "omg_add()"
  _debug2 "omg.lol Address: " "$address"
  _secure_debug2 "omg.lol authorization header: " "$authHeader"
  _debug2 "Full Domain name:" "$dnsName.$address.omg.lol"
  _debug2 "TXT value to set:" "$txtvalue"

  export _H1="$authHeader"

  endpoint="https://api.omg.lol/address/$address/dns"
  _debug2 "Endpoint" "$endpoint"

  payload='{"type": "TXT", "name":"'"$dnsName"'", "data":"'"$txtvalue"'", "ttl":30}'
  _debug2 "Payload" "$payload"

  response=$(_post "$payload" "$endpoint" "" "POST" "application/json")

  omg_validate_add "$response" "$dnsName.$address" "$txtvalue"
}

omg_validate_add() {
  response=$1
  name=$2
  content=$3

  _debug "Validating DNS record addition"
  _debug2 "omg_validate_add()"
  _debug2 "Response" "$response"
  _debug2 "DNS Name" "$name"
  _debug2 "DNS value" "$content"

  _jsonResponseCheck "$response" "success" "true"
  if [ "1" = "$?" ]; then
    _err "Response did not report success"
    return 1
  fi

  _jsonResponseCheck "$response" "message" "Your DNS record was created successfully."
  if [ "1" = "$?" ]; then
    _err "Response message did not indicate DNS record was successfully created"
    return 1
  fi

  _jsonResponseCheck "$response" "name" "$name"
  if [ "1" = "$?" ]; then
    _err "Response DNS Name did not match the response received"
    return 1
  fi

  _jsonResponseCheck "$response" "content" "$content"
  if [ "1" = "$?" ]; then
    _err "Response DNS Name did not match the response received"
    return 1
  fi

  _info "Record Created successfully"
  return 0
}

omg_getRecords() {
  address=$1
  authHeader=$2
  dnsName=$3
  txtValue=$4

  _debug2 "omg_getRecords()"
  _debug2 "omg.lol Address: " "$address"
  _secure_debug2 "omg.lol Auth Header: " "$authHeader"
  _debug2 "omg.lol DNS name:" "$dnsName"
  _debug2 "txt Value" "$txtValue"

  export _H1="$authHeader"

  endpoint="https://api.omg.lol/address/$address/dns"
  _debug2 "Endpoint" "$endpoint"

  payload=$(_get "$endpoint")

  _debug2 "Received Payload:" "$payload"

  # Reformat the JSON to be more parseable
  recordID=$(echo "$payload" | _stripWhitespace)
  recordID=$(echo "$recordID" | _exposeJsonArray)

  # Now find the one with the right value, and caputre its ID
  recordID=$(echo "$recordID" | grep -- "$txtValue" | grep -i -- "$dnsName.$address")
  _getJsonElement "$recordID" "id"
}

omg_delete() {
  address=$1
  authHeader=$2
  dnsName=$3
  txtValue=$4

  _info "Deleting DNS entry for $dnsName with value $txtValue"
  _debug2 "omg_delete()"
  _debug2 "omg.lol Address: " "$address"
  _secure_debug2 "omg.lol Auth Header: " "$authHeader"
  _debug2 "Full Domain name:" "$dnsName.$address.omg.lol"
  _debug2 "txt Value" "$txtValue"

  record=$(omg_getRecords "$address" "$authHeader" "$dnsName" "$txtvalue")
  if [ "" = "$record" ]; then
    _err "DNS record $address not found!"
    return 1
  fi

  endpoint="https://api.omg.lol/address/$address/dns/$record"
  _debug2 "Endpoint" "$endpoint"

  export _H1="$authHeader"
  output=$(_post "" "$endpoint" "" "DELETE")

  _debug2 "Response" "$output"

  omg_validate_delete "$output"
}

# Validate the response on request to delete.
# Confirm status is success and message indicates deletion was successful.
# Input: Response - HTTP response received from delete request
omg_validate_delete() {
  response=$1

  _info "Validating DNS record deletion"
  _debug2 "omg_validate_delete()"
  _debug2 "Response" "$response"

  _jsonResponseCheck "$output" "success" "true"
  if [ "1" = "$?" ]; then
    _err "Response did not report success"
    return 1
  fi

  _jsonResponseCheck "$output" "message" "OK, your DNS record has been deleted."
  if [ "1" = "$?" ]; then
    _err "Response message did not indicate DNS record was successfully deleted"
    return 1
  fi

  _info "Record deleted successfully"
  return 0
}

########## Utility Functions #####################################
# All utility functions only log at debug3
_jsonResponseCheck() {
  response=$1
  field=$2
  correct=$3

  correct=$(echo "$correct" | _lower_case)

  _debug3 "jsonResponseCheck()"
  _debug3 "Response to parse" "$response"
  _debug3 "Field to get response from" "$field"
  _debug3 "What is the correct response" "$correct"

  responseValue=$(_jsonGetLastResponse "$response" "$field")

  if [ "$responseValue" != "$correct" ]; then
    _debug3 "Expected: $correct"
    _debug3 "Actual: $responseValue"
    return 1
  else
    _debug3 "Matched: $responseValue"
  fi
  return 0
}

_jsonGetLastResponse() {
  response=$1
  field=$2

  _debug3 "jsonGetLastResponse()"
  _debug3 "Response provided" "$response"
  _debug3 "Field to get responses for" "$field"

  responseValue=$(echo "$response" | grep -- "\"$field\"" | cut -f2 -d":")

  _debug3 "Response lines found:" "$responseValue"

  responseValue=$(echo "$responseValue" | sed 's/^ //g' | sed 's/^"//g' | sed 's/\\"//g')
  responseValue=$(echo "$responseValue" | sed 's/,$//g' | sed 's/"$//g')
  responseValue=$(echo "$responseValue" | _lower_case)

  _debug3 "Responses found" "$responseValue"
  _debug3 "Response Selected" "$(echo "$responseValue" | tail -1)"

  echo "$responseValue" | tail -1
}

_stripWhitespace() {
  tr -d '\n' | tr -d '\r' | tr -d '\t' | sed -r 's/ +/ /g' | sed 's/\\"//g'
}

_exposeJsonArray() {
  sed -r 's/.*\[//g' | tr '}' '|' | tr '{' '|' | sed 's/|, |/|/g' | tr '|' '\n'
}

_getJsonElement() {
  content=$1
  field=$2

  _debug3 "_getJsonElement()"
  _debug3 "Input JSON element" "$content"
  _debug3 "JSON element to isolate" "$field"

  # With a single JSON entry to parse, convert commas to newlines puts each element on
  # its own line - which then allows us to just grep teh name, remove the key, and
  # isolate the value
  output=$(echo "$content" | tr ',' '\n' | grep -- "\"$field\":" | sed 's/.*: //g')

  _debug3 "String before unquoting: $output"

  _unquoteString "$output"
}

_createAuthHeader() {
  apikey=$1

  _debug3 "_createAuthHeader()"
  _secure_debug3 "Provided API Key" "$apikey"

  authheader="Authorization: Bearer $apikey"
  _secure_debug3 "Authorization Header" "$authheader"
  echo "$authheader"
}

_getDnsRecordName() {
  fqdn=$1
  address=$2

  _debug3 "_getDnsRecordName()"
  _debug3 "FQDN" "$fqdn"
  _debug3 "omg.lol Address" "$address"

  echo "$fqdn" | sed 's/\.omg\.lol//g' | sed 's/\.'"$address"'$//g'
}

_unquoteString() {
  output=$1
  quotes=0

  _debug3 "_unquoteString()"
  _debug3 "Possibly quoted string" "$output"

  _startswith "$output" "\""
  if [ $? ]; then
    quotes=$((quotes + 1))
  fi

  _endswith "$output" "\""
  if [ $? ]; then
    quotes=$((quotes + 1))
  fi

  _debug3 "Original String: $output"
  _debug3 "Quotes found: $quotes"

  if [ $((quotes)) -gt 1 ]; then
    output=$(echo "$output" | sed 's/^"//g' | sed 's/"$//g')
    _debug3 "Quotes removed: $output"
  fi

  echo "$output"
}
