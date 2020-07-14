#!/bin/bash

# Here is a script to add/remove TXT records to DNS Server on Synology DSM
#
# Author: Arabezar (on github) aka Arkadii Zhuchenko ©13.07.2020
#
#returns 0 means success, otherwise error.

_DNS_TTL="1"

########  Public functions #####################

dns_synology_dsm_add() {

  _info "Using API for Synology DSM - adding TXT to Synology DNS Server"
  
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  maindomain="${fulldomain//_acme-challenge\./}"
  _debug3 maindomain "$maindomain"

  # WebAPI-call can be replaced by adding line to the "/var/packages/DNSServer/target/named/etc/zone/master/$maindomain" file
  response=$(synowebapi --exec api=SYNO.DNSServer.Zone.Record method=create version=1 runner=admin \
    zone_name='"'"${maindomain}"'"' \
    domain_name='"'"${maindomain}"'"' \
    rr_owner='"'"${fulldomain}"\.'"' \
    rr_ttl='"'${_DNS_TTL}'"' \
    rr_type='"'"TXT"'"' \
    rr_info='"'"${txtvalue}"'"' 2> /dev/null)

  _debug3 response "$response"

  if [ "$(echo "$response" | jq '.success')" == true ]; then
      return 0
  fi

  return 1
}

dns_synology_dsm_rm() {

  _info "Using API for Synology DSM - removing TXT from Synology DNS Server"
  
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  maindomain="${fulldomain//_acme-challenge\./}"
  _debug3 maindomain "$maindomain"

  # Just removing TXT record from file (calling synowebapi failed due to some bug in specifying "items" param)
  _dns_zone_url="/var/packages/DNSServer/target/named/etc/zone/master/$maindomain"
  sed -i "/^${fulldomain}.[[:blank:]]${_DNS_TTL}[[:blank:]]TXT[[:blank:]]\"${txtvalue}\"/d" "$_dns_zone_url"

  return 0
}
