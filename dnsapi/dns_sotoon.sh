#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_sotoon_info='Sotoon.ir
Site: Sotoon.ir
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_sotoon
Options:
 Sotoon_Token API Token
 Sotoon_WorkspaceUUID Workspace UUID
Issues: github.com/acmesh-official/acme.sh/issues/6656
Author: Erfan Gholizade
'

SOTOON_API_URL="https://api.sotoon.ir/delivery/v2.1/global"

########  Public functions #####################

#Adding the txt record for validation.
#Usage: dns_sotoon_add   fulldomain   TXT_record
#Usage: dns_sotoon_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_sotoon_add() {
  fulldomain=$1
  txtvalue=$2
  _info_sotoon "Using Sotoon"

  Sotoon_Token="${Sotoon_Token:-$(_readaccountconf_mutable Sotoon_Token)}"
  Sotoon_WorkspaceUUID="${Sotoon_WorkspaceUUID:-$(_readaccountconf_mutable Sotoon_WorkspaceUUID)}"

  if [ -z "$Sotoon_Token" ]; then
    _err_sotoon "You didn't specify \"Sotoon_Token\" token yet."
    _err_sotoon "You can get yours from here https://ocean.sotoon.ir/profile/tokens"
    return 1
  fi
  if [ -z "$Sotoon_WorkspaceUUID" ]; then
    _err_sotoon "You didn't specify \"Sotoon_WorkspaceUUID\" Workspace UUID yet."
    _err_sotoon "You can get yours from here https://ocean.sotoon.ir/profile/workspaces"
    return 1
  fi

  #save the info to the account conf file.
  _saveaccountconf_mutable Sotoon_Token "$Sotoon_Token"
  _saveaccountconf_mutable Sotoon_WorkspaceUUID "$Sotoon_WorkspaceUUID"

  _debug_sotoon "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err_sotoon "invalid domain"
    return 1
  fi

  _info_sotoon "Adding record"

  _debug_sotoon _domain_id "$_domain_id"
  _debug_sotoon _sub_domain "$_sub_domain"
  _debug_sotoon _domain "$_domain"

  # First, GET the current domain zone to check for existing TXT records
  # This is needed for wildcard certs which require multiple TXT values
  _info_sotoon "Checking for existing TXT records"
  if ! _sotoon_rest GET "$_domain_id"; then
    _err_sotoon "Failed to get domain zone"
    return 1
  fi

  # Check if there are existing TXT records for this subdomain
  _existing_txt=""
  if _contains "$response" "\"$_sub_domain\""; then
    _debug_sotoon "Found existing records for $_sub_domain"
    # Extract existing TXT values from the response
    # The format is: "_acme-challenge":[{"TXT":"value1","type":"TXT","ttl":10},{"TXT":"value2",...}]
    _existing_txt=$(echo "$response" | _egrep_o "\"$_sub_domain\":\[[^]]*\]" | sed "s/\"$_sub_domain\"://")
    _debug_sotoon "Existing TXT records: $_existing_txt"
  fi

  # Build the new record entry
  _new_record="{\"TXT\":\"$txtvalue\",\"type\":\"TXT\",\"ttl\":120}"

  # If there are existing records, append to them; otherwise create new array
  if [ -n "$_existing_txt" ] && [ "$_existing_txt" != "[]" ] && [ "$_existing_txt" != "null" ]; then
    # Check if this exact TXT value already exists (avoid duplicates)
    if _contains "$_existing_txt" "\"$txtvalue\""; then
      _info_sotoon "TXT record already exists, skipping"
      return 0
    fi
    # Remove the closing bracket and append new record
    _combined_records="$(echo "$_existing_txt" | sed 's/]$//'),$_new_record]"
    _debug_sotoon "Combined records: $_combined_records"
  else
    # No existing records, create new array
    _combined_records="[$_new_record]"
  fi

  # Prepare the DNS record data in Kubernetes CRD format
  _dns_record="{\"spec\":{\"records\":{\"$_sub_domain\":$_combined_records}}}"

  _debug_sotoon "DNS record payload: $_dns_record"

  # Use PATCH to update/add the record to the domain zone
  _info_sotoon "Updating domain zone $_domain_id with TXT record"
  if _sotoon_rest PATCH "$_domain_id" "$_dns_record"; then
    if _contains "$response" "$txtvalue" || _contains "$response" "\"$_sub_domain\""; then
      _info_sotoon "Added, OK"
      return 0
    else
      _debug_sotoon "Response: $response"
      _err_sotoon "Add txt record error."
      return 1
    fi
  fi

  _err_sotoon "Add txt record error."
  return 1
}

#Remove the txt record after validation.
#Usage: dns_sotoon_rm   fulldomain   TXT_record
#Usage: dns_sotoon_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_sotoon_rm() {
  fulldomain=$1
  txtvalue=$2
  _info_sotoon "Using Sotoon"
  _debug_sotoon fulldomain "$fulldomain"
  _debug_sotoon txtvalue "$txtvalue"

  Sotoon_Token="${Sotoon_Token:-$(_readaccountconf_mutable Sotoon_Token)}"
  Sotoon_WorkspaceUUID="${Sotoon_WorkspaceUUID:-$(_readaccountconf_mutable Sotoon_WorkspaceUUID)}"

  _debug_sotoon "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err_sotoon "invalid domain"
    return 1
  fi
  _debug_sotoon _domain_id "$_domain_id"
  _debug_sotoon _sub_domain "$_sub_domain"
  _debug_sotoon _domain "$_domain"

  _info_sotoon "Removing TXT record"

  # First, GET the current domain zone to check for existing TXT records
  if ! _sotoon_rest GET "$_domain_id"; then
    _err_sotoon "Failed to get domain zone"
    return 1
  fi

  # Check if there are existing TXT records for this subdomain
  _existing_txt=""
  if _contains "$response" "\"$_sub_domain\""; then
    _debug_sotoon "Found existing records for $_sub_domain"
    _existing_txt=$(echo "$response" | _egrep_o "\"$_sub_domain\":\[[^]]*\]" | sed "s/\"$_sub_domain\"://")
    _debug_sotoon "Existing TXT records: $_existing_txt"
  fi

  # If no existing records, nothing to remove
  if [ -z "$_existing_txt" ] || [ "$_existing_txt" = "[]" ] || [ "$_existing_txt" = "null" ]; then
    _info_sotoon "No TXT records found, nothing to remove"
    return 0
  fi

  # Remove the specific TXT value from the array
  # This handles the case where there are multiple TXT values (wildcard certs)
  _remaining_records=$(echo "$_existing_txt" | sed "s/{\"TXT\":\"$txtvalue\"[^}]*},*//g" | sed 's/,]/]/g' | sed 's/\[,/[/g')
  _debug_sotoon "Remaining records after removal: $_remaining_records"

  # If no records remain, set to null to remove the subdomain entirely
  if [ "$_remaining_records" = "[]" ] || [ -z "$_remaining_records" ]; then
    _dns_record="{\"spec\":{\"records\":{\"$_sub_domain\":null}}}"
  else
    _dns_record="{\"spec\":{\"records\":{\"$_sub_domain\":$_remaining_records}}}"
  fi

  _debug_sotoon "Remove record payload: $_dns_record"

  # Use PATCH to remove the record from the domain zone
  if _sotoon_rest PATCH "$_domain_id" "$_dns_record"; then
    _info_sotoon "Record removed, OK"
    return 0
  else
    _debug_sotoon "Response: $response"
    _err_sotoon "Error removing record"
    return 1
  fi
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=1
  p=1

  _debug_sotoon "Getting root domain for: $domain"
  _debug_sotoon "Sotoon WorkspaceUUID: $Sotoon_WorkspaceUUID"

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug_sotoon "Checking domain part: $h"

    if [ -z "$h" ]; then
      #not valid
      _err_sotoon "Could not find valid domain"
      return 1
    fi

    _debug_sotoon "Fetching domain zones from Sotoon API"
    if ! _sotoon_rest GET ""; then
      _err_sotoon "Failed to get domain zones from Sotoon API"
      _err_sotoon "Please check your Sotoon_Token, Sotoon_WorkspaceUUID"
      return 1
    fi

    _debug2_sotoon "API Response: $response"

    # Check if the response contains our domain
    # Sotoon API uses Kubernetes CRD format with spec.origin for domain matching
    if _contains "$response" "\"origin\":\"$h\""; then
      _debug_sotoon "Found domain by origin: $h"

      # In Kubernetes CRD format, the metadata.name is the resource identifier
      # The name can be either:
      # 1. Same as origin
      # 2. Origin with dots replaced by hyphens
      # We check both patterns in the response to determine which one exists

      # Convert origin to hyphenated version for checking
      _h_hyphenated=$(echo "$h" | tr '.' '-')

      # Check if the hyphenated name exists in the response
      if _contains "$response" "\"name\":\"$_h_hyphenated\""; then
        _domain_id="$_h_hyphenated"
        _debug_sotoon "Found domain ID (hyphenated): $_domain_id"
      # Check if the origin itself is used as name
      elif _contains "$response" "\"name\":\"$h\""; then
        _domain_id="$h"
        _debug_sotoon "Found domain ID (same as origin): $_domain_id"
      else
        # Fallback: use the hyphenated version (more common)
        _domain_id="$_h_hyphenated"
        _debug_sotoon "Using hyphenated domain ID as fallback: $_domain_id"
      fi

      if [ -n "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain=$h
        _debug_sotoon "Domain ID (metadata.name): $_domain_id"
        _debug_sotoon "Sub domain: $_sub_domain"
        _debug_sotoon "Domain (origin): $_domain"
        return 0
      fi
      _err_sotoon "Found domain $h but could not extract domain ID"
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_sotoon_rest() {
  mtd="$1"
  resource_id="$2"
  data="$3"

  token_trimmed=$(echo "$Sotoon_Token" | tr -d '"')

  # Construct the API endpoint
  _api_path="$SOTOON_API_URL/workspaces/$Sotoon_WorkspaceUUID/domainzones"

  if [ -n "$resource_id" ]; then
    _api_path="$_api_path/$resource_id"
  fi

  _debug_sotoon "API Path: $_api_path"
  _debug_sotoon "Method: $mtd"

  # Set authorization header - Sotoon API uses Bearer token
  export _H1="Authorization: Bearer $token_trimmed"

  if [ "$mtd" = "GET" ]; then
    # GET request
    _debug_sotoon "GET" "$_api_path"
    response="$(_get "$_api_path")"
  elif [ "$mtd" = "PATCH" ]; then
    # PATCH Request
    export _H2="Content-Type: application/merge-patch+json"
    _debug_sotoon data "$data"
    response="$(_post "$data" "$_api_path" "" "$mtd")"
  else
    _err_sotoon "Unknown method: $mtd"
    return 1
  fi

  _debug2_sotoon response "$response"
  return 0
}

#Wrappers for logging
_info_sotoon() {
  _info "[Sotoon]" "$@"
}

_err_sotoon() {
  _err "[Sotoon]" "$@"
}

_debug_sotoon() {
  _debug "[Sotoon]" "$@"
}

_debug2_sotoon() {
  _debug2 "[Sotoon]" "$@"
}
