#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_dnsservices_info='DNS.Services
Site: DNS.Services
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_dnsservices
Options:
 DnsServices_Username Username
 DnsServices_Password Password
Issues: github.com/acmesh-official/acme.sh/issues/4152
Author: Bjarke Bruun <bbruun@gmail.com>
'

DNSServices_API=https://dns.services/api

########  Public functions #####################

#Usage: dns_dnsservices_add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnsservices_add() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Using dns.services to create ACME DNS challenge"
  _debug2 add_fulldomain "$fulldomain"
  _debug2 add_txtvalue "$txtvalue"

  # Read username/password from environment or .acme.sh/accounts.conf
  DnsServices_Username="${DnsServices_Username:-$(_readaccountconf_mutable DnsServices_Username)}"
  DnsServices_Password="${DnsServices_Password:-$(_readaccountconf_mutable DnsServices_Password)}"
  if [ -z "$DnsServices_Username" ] || [ -z "$DnsServices_Password" ]; then
    DnsServices_Username=""
    DnsServices_Password=""
    _err "You didn't specify dns.services api username and password yet."
    _err "Set environment variables DnsServices_Username and DnsServices_Password"
    return 1
  fi

  # Setup GET/POST/DELETE headers
  _setup_headers

  #save the credentials to the account conf file.
  _saveaccountconf_mutable DnsServices_Username "$DnsServices_Username"
  _saveaccountconf_mutable DnsServices_Password "$DnsServices_Password"

  if ! _contains "$DnsServices_Username" "@"; then
    _err "It seems that the username variable DnsServices_Username has not been set/left blank"
    _err "or is not a valid email. Please correct and try again."
    return 1
  fi

  if ! _get_root "${fulldomain}"; then
    _err "Invalid domain ${fulldomain}"
    return 1
  fi

  if ! createRecord "$fulldomain" "${txtvalue}"; then
    _err "Error creating TXT record in domain $fulldomain in $rootZoneName"
    return 1
  fi

  _debug2 challenge-created "Created $fulldomain"
  return 0
}

#Usage: fulldomain txtvalue
#Description: Remove the txt record after validation.
dns_dnsservices_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Using dns.services to remove DNS record $fulldomain TXT $txtvalue"
  _debug rm_fulldomain "$fulldomain"
  _debug rm_txtvalue "$txtvalue"

  # Read username/password from environment or .acme.sh/accounts.conf
  DnsServices_Username="${DnsServices_Username:-$(_readaccountconf_mutable DnsServices_Username)}"
  DnsServices_Password="${DnsServices_Password:-$(_readaccountconf_mutable DnsServices_Password)}"
  if [ -z "$DnsServices_Username" ] || [ -z "$DnsServices_Password" ]; then
    DnsServices_Username=""
    DnsServices_Password=""
    _err "You didn't specify dns.services api username and password yet."
    _err "Set environment variables DnsServices_Username and DnsServices_Password"
    return 1
  fi

  # Setup GET/POST/DELETE headers
  _setup_headers

  if ! _get_root "${fulldomain}"; then
    _err "Invalid domain ${fulldomain}"
    return 1
  fi

  _debug2 rm_rootDomainInfo "found root domain $rootZoneName for $fulldomain"

  if ! deleteRecord "${fulldomain}" "${txtvalue}"; then
    _err "Error removing record: $fulldomain TXT ${txtvalue}"
    return 1
  fi

  return 0
}

####################  Private functions below ##################################

_setup_headers() {
  # Set up API Headers for _get() and _post()
  # The <function>_add or <function>_rm must have been called before to work

  if [ -z "$DnsServices_Username" ] || [ -z "$DnsServices_Password" ]; then
    _err "Could not setup BASIC authentication headers, they are missing"
    return 1
  fi

  DnsServiceCredentials="$(printf "%s" "$DnsServices_Username:$DnsServices_Password" | _base64)"
  export _H1="Authorization: Basic $DnsServiceCredentials"
  export _H2="Content-Type: application/json"

  # Just return if headers are set
  return 0
}

_get_root() {
  domain="$1"
  _debug2 _get_root "Get the root domain of ${domain} for DNS API"

  # Setup _get() and _post() headers
  #_setup_headers

  result=$(_H1="$_H1" _H2="$_H2" _get "$DNSServices_API/dns")
  result2="$(printf "%s\n" "$result" | tr '[' '\n' | grep '"name"')"
  result3="$(printf "%s\n" "$result2" | tr '}' '\n' | grep '"name"' | sed "s,^\,,,g" | sed "s,$,},g")"
  useResult=""
  _debug2 _get_root "Got the following root domain(s) $result"
  _debug2 _get_root "- JSON: $result"

  if [ "$(printf "%s\n" "$result" | tr '}' '\n' | grep -c '"name"')" -gt "1" ]; then
    checkMultiZones="true"
    _debug2 _get_root "- multiple zones found"
  else
    checkMultiZones="false"
    _debug2 _get_root "- single zone found"
  fi

  # Find/isolate the root zone to work with in createRecord() and deleteRecord()
  rootZone=""
  if [ "$checkMultiZones" = "true" ]; then
    #rootZone=$(for x in $(printf "%s" "${result3}" | tr ',' '\n' | sed -n 's/.*"name":"\(.*\)",.*/\1/p'); do if [ "$(echo "$domain" | grep "$x")" != "" ]; then echo "$x"; fi; done)
    rootZone=$(for x in $(printf "%s\n" "${result3}" | tr ',' '\n' | grep name | cut -d'"' -f4); do if [ "$(echo "$domain" | grep "$x")" != "" ]; then echo "$x"; fi; done)
    if [ "$rootZone" != "" ]; then
      _debug2 _rootZone "- root zone for $domain is $rootZone"
    else
      _err "Could not find root zone for $domain, is it correctly typed?"
      return 1
    fi
  else
    rootZone=$(echo "$result" | tr '}' '\n' | _egrep_o '"name":"[^"]*' | cut -d'"' -f4)
    _debug2 _get_root "- only found 1 domain in API: $rootZone"
  fi

  if [ -z "$rootZone" ]; then
    _err "Could not find root domain for $domain - is it correctly typed?"
    return 1
  fi

  # Make sure we use the correct API zone data
  useResult="$(printf "%s\n" "${result3}" tr ',' '\n' | grep "$rootZone")"
  _debug2 _useResult "useResult=$useResult"

  # Setup variables used by other functions to communicate with DNS.Services API
  #zoneInfo=$(printf "%s\n" "$useResult" | sed -E 's,.*(zones)(.*),\1\2,g' | sed -E 's,^(.*"name":")([^"]*)"(.*)$,\2,g')
  zoneInfo=$(printf "%s\n" "$useResult" | tr ',' '\n' | grep '"name"' | cut -d'"' -f4)
  rootZoneName="$rootZone"
  subDomainName="$(printf "%s\n" "$domain" | sed "s,\.$rootZone,,g")"
  subDomainNameClean="$(printf "%s\n" "$domain" | sed "s,_acme-challenge.,,g")"
  rootZoneDomainID=$(printf "%s\n" "$useResult" | tr ',' '\n' | grep domain_id | cut -d'"' -f4)
  rootZoneServiceID=$(printf "%s\n" "$useResult" | tr ',' '\n' | grep service_id | cut -d'"' -f4)

  _debug2 _zoneInfo "Zone info from API  : $zoneInfo"
  _debug2 _get_root "Root zone name      : $rootZoneName"
  _debug2 _get_root "Root zone domain ID : $rootZoneDomainID"
  _debug2 _get_root "Root zone service ID: $rootZoneServiceID"
  _debug2 _get_root "Sub domain          : $subDomainName"

  _debug _get_root "Found valid root domain $rootZone for $subDomainNameClean"
  return 0
}

createRecord() {
  fulldomain="$1"
  txtvalue="$2"

  # Get root domain information - needed for DNS.Services API communication
  if [ -z "$rootZoneName" ] || [ -z "$rootZoneDomainID" ] || [ -z "$rootZoneServiceID" ]; then
    _get_root "$fulldomain"
  fi
  if [ -z "$rootZoneName" ] || [ -z "$rootZoneDomainID" ] || [ -z "$rootZoneServiceID" ]; then
    _err "Something happend - could not get the API zone information"
    return 1
  fi

  _debug2 createRecord "CNAME TXT value is: $txtvalue"

  # Prepare data to send to API
  data="{\"name\":\"${fulldomain}\",\"type\":\"TXT\",\"content\":\"${txtvalue}\", \"ttl\":\"10\"}"

  _debug2 createRecord "data to API: $data"
  result=$(_post "$data" "$DNSServices_API/service/$rootZoneServiceID/dns/$rootZoneDomainID/records" "" "POST")
  _debug2 createRecord "result from API: $result"

  if [ "$(echo "$result" | _egrep_o "\"success\":true")" = "" ]; then
    _err "Failed to create TXT record $fulldomain with content $txtvalue in zone $rootZoneName"
    _err "$result"
    return 1
  fi

  _info "Record \"$fulldomain TXT $txtvalue\" has been created"
  return 0
}

deleteRecord() {
  fulldomain="$1"
  txtvalue="$2"

  _log deleteRecord "Deleting $fulldomain TXT $txtvalue record"

  if [ -z "$rootZoneName" ] || [ -z "$rootZoneDomainID" ] || [ -z "$rootZoneServiceID" ]; then
    _get_root "$fulldomain"
  fi

  result="$(_H1="$_H1" _H2="$_H2" _get "$DNSServices_API/service/$rootZoneServiceID/dns/$rootZoneDomainID")"
  #recordInfo="$(echo "$result" | sed -e 's/:{/:{\n/g' -e 's/},/\n},\n/g' | grep "${txtvalue}")"
  #recordID="$(echo "$recordInfo" | sed -e 's/:{/:{\n/g' -e 's/},/\n},\n/g' | grep "${txtvalue}" | sed -E 's,.*(zones)(.*),\1\2,g' | sed -E 's,^(.*"id":")([^"]*)"(.*)$,\2,g')"
  recordID="$(printf "%s\n" "$result" | tr '}' '\n' | grep -- "$txtvalue" | tr ',' '\n' | grep '"id"' | cut -d'"' -f4)"
  _debug2 _recordID "recordID used for deletion of record: $recordID"

  if [ -z "$recordID" ]; then
    _info "Record $fulldomain TXT $txtvalue not found or already deleted"
    return 0
  else
    _debug2 deleteRecord "Found recordID=$recordID"
  fi

  _debug2 deleteRecord "DELETE request $DNSServices_API/service/$rootZoneServiceID/dns/$rootZoneDomainID/records/$recordID"
  _log "curl DELETE request $DNSServices_API/service/$rootZoneServiceID/dns/$rootZoneDomainID/records/$recordID"
  result="$(_H1="$_H1" _H2="$_H2" _post "" "$DNSServices_API/service/$rootZoneServiceID/dns/$rootZoneDomainID/records/$recordID" "" "DELETE")"
  _debug2 deleteRecord "API Delete result \"$result\""
  _log "curl API Delete result \"$result\""

  # Return OK regardless
  return 0
}
