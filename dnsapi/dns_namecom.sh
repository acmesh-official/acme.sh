#!/usr/bin/env sh

#Author: RaidenII
#Created 06/28/2017
#Updated 03/01/2018, rewrote to support name.com API v4
#Utilize name.com API to finish dns-01 verifications.
########  Public functions #####################

Namecom_API="https://api.name.com/v4"

#Usage: dns_namecom_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_namecom_add() {
  fulldomain=$1
  txtvalue=$2

  Namecom_Username="${Namecom_Username:-$(_readaccountconf_mutable Namecom_Username)}"
  Namecom_Token="${Namecom_Token:-$(_readaccountconf_mutable Namecom_Token)}"
  # First we need name.com credentials.
  if [ -z "$Namecom_Username" ]; then
    Namecom_Username=""
    _err "Username for name.com is missing."
    _err "Please specify that in your environment variable."
    return 1
  fi

  if [ -z "$Namecom_Token" ]; then
    Namecom_Token=""
    _err "API token for name.com is missing."
    _err "Please specify that in your environment variable."
    return 1
  fi
  _debug Namecom_Username "$Namecom_Username"
  _secure_debug Namecom_Token "$Namecom_Token"
  # Save them in configuration.
  _saveaccountconf_mutable Namecom_Username "$Namecom_Username"
  _saveaccountconf_mutable Namecom_Token "$Namecom_Token"

  # Login in using API
  if ! _namecom_login; then
    return 1
  fi

  # Find domain in domain list.
  if ! _namecom_get_root "$fulldomain"; then
    _err "Unable to find domain specified."
    return 1
  fi

  # Add TXT record.
  _namecom_addtxt_json="{\"host\":\"$_sub_domain\",\"type\":\"TXT\",\"answer\":\"$txtvalue\",\"ttl\":\"300\"}"
  if _namecom_rest POST "domains/$_domain/records" "$_namecom_addtxt_json"; then
    _retvalue=$(echo "$response" | _egrep_o "\"$_sub_domain\"")
    if [ "$_retvalue" ]; then
      _info "Successfully added TXT record, ready for validation."
      return 0
    else
      _err "Unable to add the DNS record."
      return 1
    fi
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_namecom_rm() {
  fulldomain=$1
  txtvalue=$2

  Namecom_Username="${Namecom_Username:-$(_readaccountconf_mutable Namecom_Username)}"
  Namecom_Token="${Namecom_Token:-$(_readaccountconf_mutable Namecom_Token)}"
  if ! _namecom_login; then
    return 1
  fi

  # Find domain in domain list.
  if ! _namecom_get_root "$fulldomain"; then
    _err "Unable to find domain specified."
    return 1
  fi

  # Get the record id.
  if _namecom_rest GET "domains/$_domain/records"; then
    _record_id=$(echo "$response" | _egrep_o "\"id\":[0-9]+,\"domainName\":\"$_domain\",\"host\":\"$_sub_domain\",\"fqdn\":\"$fulldomain.\",\"type\":\"TXT\",\"answer\":\"$txtvalue\"" | cut -d \" -f 3 | _egrep_o [0-9]+)
    _debug record_id "$_record_id"
    if [ "$_record_id" ]; then
      _info "Successfully retrieved the record id for ACME challenge."
    else
      _err "Unable to retrieve the record id."
      return 1
    fi
  fi

  # Remove the DNS record using record id.
  if _namecom_rest DELETE "domains/$_domain/records/$_record_id"; then
    _info "Successfully removed the TXT record."
    return 0
  else
    _err "Unable to delete record id."
    return 1
  fi
}

####################  Private functions below ##################################
_namecom_rest() {
  method=$1
  param=$2
  data=$3

  export _H1="Authorization: Basic $_namecom_auth"
  export _H2="Content-Type: application/json"

  if [ "$method" != "GET" ]; then
    response="$(_post "$data" "$Namecom_API/$param" "" "$method")"
  else
    response="$(_get "$Namecom_API/$param")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $param"
    return 1
  fi

  _debug2 response "$response"
  return 0
}

_namecom_login() {
  # Auth string
  # Name.com API v4 uses http basic auth to authenticate
  # need to convert the token for http auth
  _namecom_auth=$(printf "%s:%s" "$Namecom_Username" "$Namecom_Token" | _base64)

  if _namecom_rest GET "hello"; then
    retcode=$(echo "$response" | _egrep_o "\"username\"\:\"$Namecom_Username\"")
    if [ "$retcode" ]; then
      _info "Successfully logged in."
    else
      _err "$response"
      _err "Please add your ip to api whitelist"
      _err "Logging in failed."
      return 1
    fi
  fi
}

_namecom_get_root() {
  full_domain=$1

  # Strip the subdomain from the full domain
  domain=$(echo "$full_domain" | sed 's/.*\.\([^.]*\.[^.]*\)$/\1/')

  # Initialize variables for pagination
  _page=1

  while true; do
    if ! _namecom_rest GET "domains?page=$_page&perPage=1000"; then
      _debug "Error: Failed to retrieve domains from API"
      return 1
    fi

    _debug "Response for $full_domain: $response"

    # Check if the domain is found in the current page
    if echo "$response" | grep -q "\"domainName\":\"$domain\""; then
      _debug "Domain $domain found in the response"
      # Extract the subdomain from the full domain
      _sub_domain=$(echo "$full_domain" | sed "s/\.$domain$//")
      _domain=$domain
      _debug "Subdomain for $full_domain: $_sub_domain"
      _debug "Domain: $_domain"
      return 0
    else
      _debug "Domain $domain not found in the current page"
    fi

    # Check if there are more pages
    if echo "$response" | grep -q '"nextPage":'; then
      _page=$(_math "$_page" + 1)
      _debug "Moving to the next page $_page for domain $full_domain"
    else
      _debug "No more pages to search for domain $full_domain"
      break
    fi
  done

  _debug "Domain $domain not found in any page"
  return 1
}
