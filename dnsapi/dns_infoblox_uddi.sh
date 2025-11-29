#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_infoblox_uddi_info='Infoblox UDDI
Site: Infoblox.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_infoblox_uddi
Options:
 Infoblox_UDDI_Key API Key for Infoblox UDDI
 Infoblox_Portal URL, e.g. "csp.infoblox.com" or "csp.eu.infoblox.com"
Issues: github.com/acmesh-official/acme.sh/issues
Author: Stefan Riegel
'

Infoblox_UDDI_Api="https://"

########  Public functions #####################

#Usage: dns_infoblox_uddi_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_infoblox_uddi_add() {
  fulldomain=$1
  txtvalue=$2

  Infoblox_UDDI_Key="${Infoblox_UDDI_Key:-$(_readaccountconf_mutable Infoblox_UDDI_Key)}"
  Infoblox_Portal="${Infoblox_Portal:-$(_readaccountconf_mutable Infoblox_Portal)}"

  _info "Using Infoblox UDDI API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if [ -z "$Infoblox_UDDI_Key" ] || [ -z "$Infoblox_Portal" ]; then
    Infoblox_UDDI_Key=""
    Infoblox_Portal=""
    _err "You didn't specify the Infoblox UDDI key or server (Infoblox_UDDI_Key; Infoblox_Portal)."
    _err "Please set them via EXPORT Infoblox_UDDI_Key=your_key, EXPORT Infoblox_Portal=csp.infoblox.com and try again."
    return 1
  fi

  _saveaccountconf_mutable Infoblox_UDDI_Key "$Infoblox_UDDI_Key"
  _saveaccountconf_mutable Infoblox_Portal "$Infoblox_Portal"

  export _H1="Authorization: Token $Infoblox_UDDI_Key"
  export _H2="Content-Type: application/json"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting existing txt records"
  _infoblox_rest GET "dns/record?_filter=type%20eq%20'TXT'%20and%20name_in_zone%20eq%20'$_sub_domain'%20and%20zone%20eq%20'$_domain_id'"

  _info "Adding record"
  body="{\"type\":\"TXT\",\"name_in_zone\":\"$_sub_domain\",\"zone\":\"$_domain_id\",\"ttl\":120,\"inheritance_sources\":{\"ttl\":{\"action\":\"override\"}},\"rdata\":{\"text\":\"$txtvalue\"}}"

  if _infoblox_rest POST "dns/record" "$body"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
      return 0
    elif _contains "$response" '"error"'; then
      # Check if record already exists
      if _contains "$response" "already exists" || _contains "$response" "duplicate"; then
        _info "Already exists, OK"
        return 0
      else
        _err "Add txt record error."
        _err "Response: $response"
        return 1
      fi
    else
      _info "Added, OK"
      return 0
    fi
  fi
  _err "Add txt record error."
  return 1
}

#Usage: dns_infoblox_uddi_rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_infoblox_uddi_rm() {
  fulldomain=$1
  txtvalue=$2

  Infoblox_UDDI_Key="${Infoblox_UDDI_Key:-$(_readaccountconf_mutable Infoblox_UDDI_Key)}"
  Infoblox_Portal="${Infoblox_Portal:-$(_readaccountconf_mutable Infoblox_Portal)}"

  if [ -z "$Infoblox_UDDI_Key" ] || [ -z "$Infoblox_Portal" ]; then
    _err "Credentials not found"
    return 1
  fi

  _info "Using Infoblox UDDI API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  export _H1="Authorization: Token $Infoblox_UDDI_Key"
  export _H2="Content-Type: application/json"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records to delete"
  # Filter by txtvalue to support wildcard certs (multiple TXT records)
  filter="type%20eq%20'TXT'%20and%20name_in_zone%20eq%20'$_sub_domain'%20and%20zone%20eq%20'$_domain_id'%20and%20rdata.text%20eq%20'$txtvalue'"
  _infoblox_rest GET "dns/record?_filter=$filter"

  if ! _contains "$response" '"results"'; then
    _info "Don't need to remove, record not found."
    return 0
  fi

  record_id=$(echo "$response" | _egrep_o '"id":[[:space:]]*"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
  _debug "record_id" "$record_id"

  if [ -z "$record_id" ]; then
    _info "Don't need to remove, record not found."
    return 0
  fi

  # Extract UUID from the full record ID (format: dns/record/uuid)
  record_uuid=$(echo "$record_id" | sed 's|.*/||')
  _debug "record_uuid" "$record_uuid"

  if ! _infoblox_rest DELETE "dns/record/$record_uuid"; then
    _err "Delete record error."
    return 1
  fi

  _info "Removed record successfully"
  return 0
}

####################  Private functions below ##################################

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=dns/auth_zone/xxxx-xxxx
_get_root() {
  domain=$1
  i=1
  p=1

  # Remove _acme-challenge prefix if present
  domain_no_acme=$(echo "$domain" | sed 's/^_acme-challenge\.//')

  while true; do
    h=$(printf "%s" "$domain_no_acme" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      # not valid
      return 1
    fi

    # Query for the zone with both trailing dot and without
    filter="fqdn%20eq%20'$h.'%20or%20fqdn%20eq%20'$h'"
    if ! _infoblox_rest GET "dns/auth_zone?_filter=$filter"; then
      # API error - don't continue if we get auth errors
      if _contains "$response" "401" || _contains "$response" "Authorization"; then
        _err "Authentication failed. Please check your Infoblox_UDDI_Key."
        return 1
      fi
      # For other errors, continue to parent domain
      p=$i
      i=$((i + 1))
      continue
    fi

    # Check if response contains results (even if empty)
    if _contains "$response" '"results"'; then
      # Extract zone ID - must match the pattern dns/auth_zone/...
      zone_id=$(echo "$response" | _egrep_o '"id":[[:space:]]*"dns/auth_zone/[^"]*"' | _head_n 1 | cut -d '"' -f 4)
      if [ -n "$zone_id" ]; then
        # Found the zone
        _domain="$h"
        _domain_id="$zone_id"

        # Calculate subdomain
        if [ "$_domain" = "$domain" ]; then
          _sub_domain=""
        else
          _cutlength=$((${#domain} - ${#_domain} - 1))
          _sub_domain=$(printf "%s" "$domain" | cut -c "1-$_cutlength")
        fi

        return 0
      fi
    fi

    p=$i
    i=$((i + 1))
  done

  return 1
}

# _infoblox_rest GET "dns/record?_filter=..."
# _infoblox_rest POST "dns/record" "{json body}"
# _infoblox_rest DELETE "dns/record/uuid"
_infoblox_rest() {
  method=$1
  ep="$2"
  data="$3"

  _debug "$ep"

  # Ensure credentials are available (when called from _get_root)
  Infoblox_UDDI_Key="${Infoblox_UDDI_Key:-$(_readaccountconf_mutable Infoblox_UDDI_Key)}"
  Infoblox_Portal="${Infoblox_Portal:-$(_readaccountconf_mutable Infoblox_Portal)}"

  Infoblox_UDDI_Api="https://$Infoblox_Portal/api/ddi/v1"
  export _H1="Authorization: Token $Infoblox_UDDI_Key"
  export _H2="Content-Type: application/json"

  # Debug (masked)
  _tok_len=$(printf "%s" "$Infoblox_UDDI_Key" | wc -c | tr -d ' \n')
  _debug2 "Auth header set" "Token len=${_tok_len} on $Infoblox_Portal"

  if [ "$method" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$Infoblox_UDDI_Api/$ep" "" "$method")"
  else
    response="$(_get "$Infoblox_UDDI_Api/$ep")"
  fi

  _ret="$?"
  _debug2 response "$response"

  if [ "$_ret" != "0" ]; then
    _err "Error: $ep"
    return 1
  fi

  return 0
}
