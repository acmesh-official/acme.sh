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

  zone_url="https://$Infoblox_Portal/api/ddi/v1/dns/auth_zone"
  zone_result="$(_get "$zone_url")"
  _debug2 "zone_result: $zone_result"

  if [ "$?" != "0" ]; then
    _err "Error fetching zones from Infoblox API"
    return 1
  fi

  fulldomain_no_acme=$(echo "$fulldomain" | sed 's/^_acme-challenge\.//')
  _debug "Looking for zone matching domain: $fulldomain_no_acme"

  zone_fqdn=""
  temp_domain="$fulldomain_no_acme"

  while [ -n "$temp_domain" ]; do
    _debug "Checking if '$temp_domain' is a zone..."
    if echo "$zone_result" | grep -q "\"fqdn\":\"$temp_domain\"" || echo "$zone_result" | grep -q "\"fqdn\":\"$temp_domain\.\""; then
      zone_fqdn="$temp_domain"
      _debug "Found matching zone: $zone_fqdn"
      break
    fi
    temp_domain=$(echo "$temp_domain" | sed 's/^[^.]*\.//')
    if ! echo "$temp_domain" | grep -q '\.'; then
      break
    fi
  done

  if [ -z "$zone_fqdn" ]; then
    _err "Could not determine zone for domain $fulldomain"
    _err "Available zones: $(echo "$zone_result" | _egrep_o '"fqdn":"[^"]*"' | sed 's/"fqdn":"//;s/"//')"
    return 1
  fi

  # Fetch exact zone_id for the matched fqdn using server-side filtering
  filter="fqdn eq '$zone_fqdn.' or fqdn eq '$zone_fqdn'"
  filter_encoded=$(_url_encode "$filter")
  zone_query="$zone_url?_filter=$filter_encoded"
  zone_lookup="$(_get "$zone_query")"
  _debug2 "zone_lookup: $zone_lookup"
  zone_id=$(echo "$zone_lookup" | _egrep_o '"id":"dns/auth_zone/[^\"]*"' | _head_n 1 | sed 's/.*"id":"\([^\"]*\)".*/\1/')

  _debug zone_id "$zone_id"

  if [ -z "$zone_id" ]; then
    _err "Could not find zone ID for $zone_fqdn"
    _debug "Zone result: $zone_result"
    return 1
  fi

  name_in_zone=$(echo "$fulldomain" | sed "s/\.$zone_fqdn\$//")
  name_in_zone=$(echo "$name_in_zone" | sed 's/\.$//')
  _debug name_in_zone "$name_in_zone"

  baseurl="https://$Infoblox_Portal/api/ddi/v1/dns/record"

  body="{\"type\":\"TXT\",\"name_in_zone\":\"$name_in_zone\",\"zone\":\"$zone_id\",\"ttl\":120,\"inheritance_sources\":{\"ttl\":{\"action\":\"override\"}},\"rdata\":{\"text\":\"$txtvalue\"}}"

  result="$(_post "$body" "$baseurl" "" "POST")"
  _debug2 result "$result"

  if echo "$result" | grep -q '"id"'; then
    record_id=$(echo "$result" | _egrep_o '"id":"[^"]*"' | head -1 | sed 's/"id":"\([^"]*\)"/\1/')
    _info "Successfully created TXT record with ID: $record_id"
    return 0
  else
    _err "Error encountered during record addition"
    _err "Response: $result"
    return 1
  fi
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

  zone_url="https://$Infoblox_Portal/api/ddi/v1/dns/auth_zone"
  zone_result="$(_get "$zone_url")"
  _debug2 "zone_result: $zone_result"

  if [ "$?" != "0" ]; then
    _err "Error fetching zones from Infoblox API"
    return 1
  fi

  fulldomain_no_acme=$(echo "$fulldomain" | sed 's/^_acme-challenge\.//')
  _debug "Looking for zone matching domain: $fulldomain_no_acme"

  zone_fqdn=""
  temp_domain="$fulldomain_no_acme"

  while [ -n "$temp_domain" ]; do
    _debug "Checking if '$temp_domain' is a zone..."
    if echo "$zone_result" | grep -q "\"fqdn\":\"$temp_domain\"" || echo "$zone_result" | grep -q "\"fqdn\":\"$temp_domain\.\""; then
      zone_fqdn="$temp_domain"
      _debug "Found matching zone: $zone_fqdn"
      break
    fi
    temp_domain=$(echo "$temp_domain" | sed 's/^[^.]*\.//')
    if ! echo "$temp_domain" | grep -q '\.'; then
      break
    fi
  done

  if [ -z "$zone_fqdn" ]; then
    _err "Could not determine zone for domain $fulldomain"
    _err "Available zones: $(echo "$zone_result" | _egrep_o '"fqdn":"[^"]*"' | sed 's/"fqdn":"//;s/"//')"
    return 1
  fi

  # Fetch exact zone_id for the matched fqdn using server-side filtering
  filter="fqdn eq '$zone_fqdn.' or fqdn eq '$zone_fqdn'"
  filter_encoded=$(_url_encode "$filter")
  zone_query="$zone_url?_filter=$filter_encoded"
  zone_lookup="$(_get "$zone_query")"
  _debug2 "zone_lookup: $zone_lookup"
  zone_id=$(echo "$zone_lookup" | _egrep_o '"id":"dns/auth_zone/[^\"]*"' | _head_n 1 | sed 's/.*"id":"\([^\"]*\)".*/\1/')

  _debug zone_id "$zone_id"

  if [ -z "$zone_id" ]; then
    _err "Could not find zone ID for $zone_fqdn"
    _debug "Zone result: $zone_result"
    return 1
  fi

  name_in_zone=$(echo "$fulldomain" | sed "s/\.$zone_fqdn\$//" | sed 's/\.$//')
  _debug name_in_zone "$name_in_zone"

  filter="type eq 'TXT' and name_in_zone eq '$name_in_zone' and zone eq '$zone_id' and rdata.text eq '$txtvalue'"
  filter_encoded=$(_url_encode "$filter")
  geturl="https://$Infoblox_Portal/api/ddi/v1/dns/record?_filter=$filter_encoded"

  result="$(_get "$geturl")"
  _debug2 result "$result"

  if echo "$result" | grep -q '"results":'; then
    record_id=$(echo "$result" | _egrep_o '"id":"dns/record/[^\"]*"' | _head_n 1 | sed 's/.*"id":"\([^\"]*\)".*/\1/')
    _debug "Found record_id: $record_id"

    if [ -n "$record_id" ]; then
      record_uuid=$(echo "$record_id" | sed 's/.*\/\([a-f0-9-]*\)$/\1/')
      _debug record_uuid "$record_uuid"

      delurl="https://$Infoblox_Portal/api/ddi/v1/dns/record/$record_uuid"
      rmResult="$(_post "" "$delurl" "" "DELETE")"

      if [ -z "$rmResult" ] || [ "$rmResult" = "{}" ]; then
        _info "Successfully deleted the txt record"
        return 0
      else
        _err "Error occurred during txt record delete"
        _err "Response: $rmResult"
        return 1
      fi
    else
      _err "Record to delete didn't match an existing record (no matching txtvalue found)"
      return 1
    fi
  else
    _err "Record to delete didn't match an existing record (no results found)"
    _debug "Response: $result"
    return 1
  fi
}
