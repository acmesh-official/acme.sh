#!/usr/bin/env sh

# shellcheck disable=SC2034
dns_arubabusiness_info='ArubaBusiness
Site: business.aruba.it
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_arubabusiness
Options:
 AB_Key Your ArubaBusiness API Key
 AB_User Your account user
 AB_Pass Your account password
'

#
# A word of warning: as of this writing, api.arubabusiness.it only supports oauth authentication using the "password" grant type.
# If you are REALLY sure you want to use it, it would be wise set up a dedicated technical user without administrative privileges
#
ARUBABUSINESS_API='https://api.arubabusiness.it'

######## Public functions ########

#
# Usage: dns_arubabusiness_add _acme-challenge.www.domain.com aaaabbbbcccc111122223333
#
# Add a new TXT record whose name and value match the given domain and value
#
# Variables
#   _full_domain: $1 - the name of the TXT record
#   _txt_value: $2 - the value of the TXT record
#   _body
#   dns_details
#   domain_id
#   dns_record_id
#   response
#
dns_arubabusiness_add() {
  _full_domain=$1
  _txt_value=$2

  if ! _ab_authenticate; then
    return 1
  fi

  if ! _ab_domain_id "$_full_domain"; then
    return 1
  fi

  if _ab_dns_record_id "$_full_domain" "$_txt_value" "$dns_details"; then
    # Multiple identical records are allowed to coexist.
    # This is very unlikely, but, in order to avoid interferences between jobs, this process is killed
    _err "A TXT record with name: $_full_domain and value: $_txt_value already exists"
    _err "Please make sure that there are no other concurrent jobs running and that the dns records are clean"
    return 1
  fi

  _body="{ \"IdDomain\": $domain_id, \"Type\": \"TXT\", \"Name\": \"$_full_domain\", \"Content\": \"\\\"$_txt_value\\\"\" }"

  _debug "Adding TXT record with name: $_full_domain and value: $_txt_value"

  if ! _ab_rest POST "api/domains/dns/record" "$_body" || _ab_is_failure_message "$response" || ! _contains "$response" "DomainId"; then
    _err "Failed to add TXT record with name: $_full_domain"
    return 1
  fi

  _info "Sleeping 10 seconds to let ArubaBusiness do its magic"
  _sleep 10

  # Refresh dns details and check that the record was really added
  if ! _ab_dns_details "$root_domain"; then
    return 1
  fi

  if ! _ab_dns_record_id "$_full_domain" "$_txt_value" "$dns_details"; then
    # This should never happen
    _err "The TXT record with name: $_full_domain was not set"
    _err "Please check that the dns records are clean"
    return 1
  fi

  _info "Added TXT record with id: $dns_record_id"
  return 0
}

#
# Usage: dns_arubabusiness_rm _acme-challenge.www.domain.com aaaabbbbcccc111122223333
#
# Remove the TXT record whose name and value match the given domain and value
#
# Variables
#   _full_domain: $1 - the name of the TXT record
#   _txt_value: $2 - the value of the TXT record
#   dns_details
#   dns_record_id
#
dns_arubabusiness_rm() {
  _full_domain=$1
  _txt_value=$2

  if ! _ab_authenticate; then
    return 1
  fi

  if ! _ab_domain_id "$_full_domain"; then
    return 1
  fi

  if ! _ab_dns_record_id "$_full_domain" "$_txt_value" "$dns_details" || [ -z "$dns_record_id" ]; then
    _err "Could not retrieve the record id for: $_full_domain"
    return 1
  fi

  _debug "Deleting TXT record: $dns_record_id"
  if ! _ab_rest DELETE "api/domains/dns/record/$dns_record_id" || _ab_is_failure_message "$response" || ! _contains "$response" "DomainId"; then
    _err "Failed to delete TXT record: $dns_record_id"
    return 1
  fi

  _info "Deleted TXT record: $dns_record_id"
  return 0
}

######## Private functions ########

#
# Usage: _ab_domain_id _acme-challenge.www.domain.com
#
# Split the input domain into subdomain + root domain and get the id of the root domain
#
# Variables
#   _full_domain: $1 - the domain whose root needs to be extracted
#   _domain_sections
#   _current_index
#   _candidate_subdomain
#   _candidate_domain
#   sub_domain
#   root_domain
#   domain_id
#   dns_details: a json containing all dns records registered on the root domain
#
# Example
#   _get_root _acme-challenge.www.domain.com
#
# Should return
#   sub_domain=_acme-challenge.www
#   root_domain=domain.com
#   domain_id=123123123123
#   dns_details="{JSON_CONTENT}"
#
_ab_domain_id() {
  _full_domain=$1

  _info "Attempting to retrieve root domain details for: $_full_domain"

  _domain_sections=$(_math "$(printf "%s" "$_full_domain" | tr '.' '\n' | wc -l)" + 1)

  if [ "$_domain_sections" -lt 1 ]; then
    _err "Invalid input $_full_domain"
    return 1
  fi

  _current_index=1
  while true; do
    _candidate_subdomain=$(if [ "$_current_index" = "1" ]; then printf ""; else printf "%s" "$_full_domain" | cut -d . -f 1-"$(_math "$_current_index" - 1)"; fi)
    _candidate_domain=$(printf "%s" "$_full_domain" | cut -d . -f "$_current_index"-"$_domain_sections")

    if ! _ab_dns_details "$_candidate_domain"; then
      _debug2 "Could not fetch dns details for: $_candidate_domain"
      _current_index=$(_math "$_current_index" + 1)

      # Fail if there are no candidates left
      if [ "$_current_index" -gt "$_domain_sections" ]; then
        _err "Could not determine the root domain for: $_full_domain"
        return 1
      fi
    else
      sub_domain="$_candidate_subdomain"
      root_domain="$_candidate_domain"
      domain_id="$(printf "%s" "$dns_details" | tr ',' '\n' | _egrep_o '"Id": .*' | _head_n 1 | cut -d : -f 2 | tr -d ' "')"

      if [ -z "$domain_id" ]; then
        _err "Could not determine the domain id for: $root_domain"
        return 1
      fi

      _debug "Retrieved root domain id: $domain_id"
      return 0
    fi
  done
}

#
# Usage: _ab_dns_record_id _acme-challenge.www.domain.com "aaaabbbbcccc111122223333" "{JSON_CONTENT}"
#
# Extract the record id of the first TXT record whose name and content match the input values
#
# Variables
#   _record_name: $1
#   _txt_value: $2
#   _dns_details: $3 - the json returned by a previous call to '_ab_dns_details() $root_domain'
#   _record_ids
#   _record_names
#   _record_types
#   _record_contents
#   _record_ids_count
#   _i
#   _j
#   dns_record_id
#
# Notes
#   TXT correspond to record type 5
#   ArubaBusiness appends a terminating dot (.) to the record name
#   The content field may contain the following character sequence: \"
#   All record names are always converted to lowercase
#
_ab_dns_record_id() {
  _record_name=$1
  _txt_value=$2
  _dns_details=$3

  _record_name_lowercase=$(printf "%s" "$_record_name" | _lower_case)

  # _record_contents contains one element less than the other lists
  _record_ids=$(printf "%s" "$_dns_details" | tr ',' '\n' | _egrep_o '"Id": .*' | cut -d : -f 2 | tr -d ' ' | tr '\n' ' ')
  _record_names=$(printf "%s" "$_dns_details" | tr ',' '\n' | _egrep_o '"Name": .*' | cut -d : -f 2 | tr -d ' "' | tr '\n' ' ')
  _record_types=$(printf "%s" "$_dns_details" | tr ',' '\n' | _egrep_o '"Type": .*' | cut -d : -f 2 | tr -d ' "' | tr '\n' ' ')
  _record_contents=$(printf "%s" "$_dns_details" | tr ',' '\n' | _egrep_o '"Content": .*' | cut -d : -f 2 | tr -d '\\ "' | tr '\n' ' ')

  _info "Looking for a TXT record matching inputs - name: $_record_name_lowercase value: $_txt_value"

  _i=2
  _record_ids_count=$(printf "%s" "$_record_ids" | tr ' ' '\n' | wc -l)
  while [ "$_i" -le "$_record_ids_count" ]; do
    _j=$(_math "$_i" - 1)

    _current_name=$(printf "%s" "$_record_names" | cut -d " " -f "$_i")
    _current_type=$(printf "%s" "$_record_types" | cut -d " " -f "$_i")
    _current_content=$(printf "%s" "$_record_contents" | cut -d " " -f "$_j")

    if [ "$_record_name_lowercase." = "$_current_name" ] && [ "5" = "$_current_type" ] && [ "$_txt_value" = "$_current_content" ]; then
      dns_record_id=$(printf "%s" "$_record_ids" | cut -d " " -f "$_i")
      _info "Found matching record with id: $dns_record_id"
      return 0
    else
      _debug2 "Record does not match - type: $_current_type name: $_current_name value: $_current_content"
    fi
    _i=$(_math "$_i" + 1)
  done

  _debug2 "No matching record was found in $_dns_details"
  return 1
}

#
# Usage: _ab_dns_details domain.com
#
# Retrieve dns info for the given input domain
#
# Variables
#   _domain: $1
#   dns_details: the json returned by the call to $ARUBABUSINESS_API/api/domains/dns/$_domain/details (if return status is 0)
#   response
#
_ab_dns_details() {
  _domain=$1

  if ! _ab_rest GET "api/domains/dns/$_domain/details" || _ab_is_failure_message "$response" || ! _contains "$response" "DomainId"; then
    return 1
  fi

  dns_details="$(printf "%s" "$response" | tr -d '\r\n')"
  return 0
}

#
# Usage: _ab_authenticate
#
# Read account conf, update domain conf and perform user authentication to acquire an access token
#
# Variables
#   AB_Key
#   AB_User
#   AB_Pass
#   AB_Token
#
_ab_authenticate() {
  AB_Key="${AB_Key:-$(_readaccountconf_mutable AB_Key)}"
  AB_User="${AB_User:-$(_readaccountconf_mutable AB_User)}"
  AB_Pass="${AB_Pass:-$(_readaccountconf_mutable AB_Pass)}"

  if [ -z "$AB_Key" ] || [ -z "$AB_User" ] || [ -z "$AB_Pass" ]; then
    AB_Key=""
    AB_User=""
    AB_Pass=""
    _err "Either the ArubaBusiness API key, the user or the password has not been defined yet."
    _err "Please configure them and try again."
    return 1
  fi

  _saveaccountconf_mutable AB_Key "$AB_Key"
  _saveaccountconf_mutable AB_User "$AB_User"
  _saveaccountconf_mutable AB_Pass "$AB_Pass"

  if ! _ab_get_token || [ -z "$AB_Token" ]; then
    _err "Failed to acquire an access token"
    return 1
  fi

  return 0
}

#
# Usage: _ab_get_token
#
# Try acquiring a temporary access token. The token should have a 24h lifespan
#
# Variables
#   _ab_user_enc
#   _ab_pass_enc
#   _ab_authdata
#   AB_User
#   AB_Pass
#   AB_Token
#   response
#   _H2
#
_ab_get_token() {
  _ab_user_enc=$(printf "%s" "$AB_User" | _url_encode)
  _ab_pass_enc=$(printf "%s" "$AB_Pass" | _url_encode)
  _ab_authdata="grant_type=password&username=$_ab_user_enc&password=$_ab_pass_enc"

  _H2="Content-Type: application/x-www-form-urlencoded"

  if ! _ab_rest POST "auth/token" "$_ab_authdata" || ! _contains "$response" "access_token"; then
    _err "Authentication failure"
    return 1
  fi

  AB_Token="$(printf "%s" "$response" | _egrep_o '"access_token":"[^\"]*"' | cut -d : -f 2 | tr -d '"')"

  if [ -z "$AB_Token" ]; then
    _err "Could not extract access token"
    return 1
  fi

  _debug "Acquired access token"
  return 0
}

#
# Usage: _ab_rest POST "example/endpoint" "password=123"
#
# Perform a REST request using the given method, endpoint and data
#
# Variables
#   _method: $1 - The http method
#   _endpoint: $2 - The api path (relative to $ARUBABUSINESS_API)
#   _data: $3 - The body of the request (optional)
#   _key_trimmed
#   _token_trimmed
#   _ret_code
#   AB_Key
#   AB_Token
#   ARUBABUSINESS_API
#   _H1
#   _H2
#   _H3
#   _H4
#
_ab_rest() {
  _method=$1
  _endpoint="$2"
  _data="$3"

  _key_trimmed=$(printf "%s" "$AB_Key" | tr -d '"')
  _token_trimmed=$(printf "%s" "$AB_Token" | tr -d '"')

  _H1="Accept: application/json"

  if [ -z "$_H2" ]; then
    # Default to application/json
    _H2="Content-Type: application/json"
  fi

  if [ "$_key_trimmed" ]; then
    _H3="Authorization-Key: $_key_trimmed"
  else
    _err "Missing Api Key"
    _ab_cleanup_headers
    return 1
  fi

  if [ "$_token_trimmed" ]; then
    _H4="Authorization: Bearer $_token_trimmed"
  else
    _debug "No access token set"
  fi

  if [ "$_method" != "GET" ]; then
    response="$(_post "$_data" "$ARUBABUSINESS_API/$_endpoint" "" "$_method")"
  else
    response="$(_get "$ARUBABUSINESS_API/$_endpoint")"
  fi

  _ret_code=$?

  _ab_cleanup_headers

  if [ "$_ret_code" != "0" ]; then
    _err "Failed to call endpoint: $_endpoint"
    return 1
  fi

  return 0
}

#
# Usage: _ab_cleanup_headers
#
# Unset header variables to avoid interfering with other calls
#
# Variables
#   _H1
#   _H2
#   _H3
#   _H4
#
_ab_cleanup_headers() {
  unset _H1 _H2 _H3 _H4
}

#
# Usage: _ab_is_failure_message "message"
#
# Check whether the input contains substrings that indicate a failure
#
# Variables
#   _message: $1
#
_ab_is_failure_message() {
  _message=$1
  if _contains "$_message" "denied" || _contains "$_message" "does not belong" || _contains "$_message" "can be performed only by the domain owner" || _contains "$_message" "error" || _contains "$_message" "reference not set to an instance of an object" || _startswith "$_message" "4-[0-9]*:"; then
    return 0
  else
    return 1
  fi
}
