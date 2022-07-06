#!/usr/bin/env sh

#This file name is "dns_dnsservices.sh"
#Script for Danish DNS registra and DNS hosting provider https://dns.services
#
#Author: Bjarke Bruun <bbruun@gmail.com>
#Report Bugs here: https://github.com/acmesh-official/acme.sh/issues/4152

# Global variable to connect to the DNS.Services API
DNSServices_API=https://dns.services/api

########  Public functions #####################

#Usage: dns_dnsservices_add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnsservices_add() {
  fulldomain=$1
  txtvalue=$2

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
  fulldomain=$1
  txtvalue=$2

  _info "Using dns.services to delete challenge $fulldomain TXT $txtvalue"
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
  domain=$1
  _debug2 _get_root "Get the root domain of ${domain} for DNS API"

  # Setup _get() and _post() headers
  #_setup_headers

  result=$(_H1="$_H1" _H2="$_H2" _get "$DNSServices_API/dns")
  _debug2 _get_root "Got the following root domain(s) $result"
  _debug2 _get_root "- JSON: $result"

  if [ "$(echo "$result" | grep -c '"name"')" -gt "1" ]; then
    checkMultiZones="true"
    _debug2 _get_root "- multiple zones found"
  else
    checkMultiZones="false"

  fi

  # Find/isolate the root zone to work with in createRecord() and deleteRecord()
  rootZone=""
  if [ "$checkMultiZones" = "true" ]; then
    rootZone=$(for zone in $(echo "$result" | tr -d '\n' ' '); do
      if [ "$(echo "$domain" | grep "$zone")" != "" ]; then
        _debug2 _get_root "- trying to figure out if $zone is in $domain"
        echo "$zone"
        break
      fi
    done)
  else
    rootZone=$(echo "$result" | grep -o '"name":"[^"]*' | cut -d'"' -f4)
    _debug2 _get_root "- only found 1 domain in API: $rootZone"
  fi

  if [ -z "$rootZone" ]; then
    _err "Could not find root domain for $domain - is it correctly typed?"
    return 1
  fi

  # Setup variables used by other functions to communicate with DNS.Services API
  zoneInfo=$(echo "$result" | sed "s,\"zones,\n&,g" | grep zones | cut -d'[' -f2 | cut -d']' -f1 | tr '}' '\n' | grep "\"$rootZone\"")
  rootZoneName="$rootZone"
  subDomainName="$(echo "$domain" | sed "s,\.$rootZone,,g")"
  subDomainNameClean="$(echo "$domain" | sed "s,_acme-challenge.,,g")"
  rootZoneDomainID=$(echo "$zoneInfo" | tr ',' '\n' | grep domain_id | cut -d'"' -f4)
  rootZoneServiceID=$(echo "$zoneInfo" | tr ',' '\n' | grep service_id | cut -d'"' -f4)

  _debug2 _get_root "Root zone name      : $rootZoneName"
  _debug2 _get_root "Root zone domain ID : $rootZoneDomainID"
  _debug2 _get_root "Root zone service ID: $rootZoneServiceID"
  _debug2 _get_root "Sub domain          : $subDomainName"

  _debug _get_root "Found valid root domain $rootZone for $subDomainNameClean"
  return 0
}

createRecord() {
  fulldomain=$1
  txtvalue="$2"

  # Get root domain information - needed for DNS.Services API communication
  if [ -z "$rootZoneName" ] || [ -z "$rootZoneDomainID" ] || [ -z "$rootZoneServiceID" ]; then
    _get_root "$fulldomain"
  fi

  _debug2 createRecord "CNAME TXT value is: $txtvalue"

  # Prepare data to send to API
  data="{\"name\":\"${fulldomain}\",\"type\":\"TXT\",\"content\":\"${txtvalue}\", \"ttl\":\"10\"}"

  _debug2 createRecord "data to API: $data"
  result=$(_post "$data" "$DNSServices_API/service/$rootZoneServiceID/dns/$rootZoneDomainID/records" "" "POST")
  _debug2 createRecord "result from API: $result"

  if [ "$(echo "$result" | grep '"success":true')" = "" ]; then
    _err "Failed to create TXT record $fulldomain with content $txtvalue in zone $rootZoneName"
    _err "$result"
    return 1
  fi

  _info "Record \"$fulldomain TXT $txtvalue\" has been created"
  return 0
}

deleteRecord() {
  fulldomain=$1
  txtvalue=$2

  if [ "$(echo "$fulldomain" | grep "_acme-challenge")" = "" ]; then
    _err "The script tried to delete the record $fulldomain which is not the above created ACME challenge"
    return 1
  fi

  _debug2 deleteRecord "Deleting $fulldomain TXT $txtvalue record"

  if [ -z "$rootZoneName" ] || [ -z "$rootZoneDomainID" ] || [ -z "$rootZoneServiceID" ]; then
    _get_root "$fulldomain"
  fi

  result="$(_H1="$_H1" _H2="$_H2" _get "$DNSServices_API/service/$rootZoneServiceID/dns/$rootZoneDomainID")"
  recordInfo="$(echo "$result" | tr '}' '\n' | grep "\"name\":\"${fulldomain}" | grep "\"content\":\"" | grep "${txtvalue}")"
  _debug2 deleteRecord "recordInfo=$recordInfo"
  recordID="$(echo "$recordInfo" | tr ',' '\n' | grep -E "\"id\":\"[0-9]+\"" | cut -d'"' -f4)"

  if [ -z "$recordID" ]; then
    _info "Record $fulldomain TXT $txtvalue not found or already deleted"
    return 0
  else
    _debug2 deleteRecord "Found recordID=$recordID"
  fi

  _debug2 deleteRecord "DELETE request $DNSServices_API/service/$rootZoneServiceID/dns/$rootZoneDomainID/records/$recordID"
  result="$(_H1="$_H1" _H2="$_H2" _post "" "$DNSServices_API/service/$rootZoneServiceID/dns/$rootZoneDomainID/records/$recordID" "" "DELETE")"
  _debug2 deleteRecord "API Delete result \"$result\""

  # Return OK regardless
  return 0
}
