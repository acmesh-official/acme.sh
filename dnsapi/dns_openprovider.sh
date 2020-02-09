#!/usr/bin/env sh

# This is the OpenProvider API wrapper for acme.sh
#
# Author: Sylvia van Os
# Report Bugs here: https://github.com/acmesh-official/acme.sh/issues/2104
#
#     export OPENPROVIDER_USER="username"
#     export OPENPROVIDER_PASSWORDHASH="hashed_password"
#
# Usage:
#     acme.sh --issue --dns dns_openprovider -d example.com

OPENPROVIDER_API="https://api.openprovider.eu/"
#OPENPROVIDER_API="https://api.cte.openprovider.eu/" # Test API

########  Public functions #####################

#Usage: dns_openprovider_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_openprovider_add() {
  fulldomain="$1"
  txtvalue="$2"

  OPENPROVIDER_USER="${OPENPROVIDER_USER:-$(_readaccountconf_mutable OPENPROVIDER_USER)}"
  OPENPROVIDER_PASSWORDHASH="${OPENPROVIDER_PASSWORDHASH:-$(_readaccountconf_mutable OPENPROVIDER_PASSWORDHASH)}"

  if [ -z "$OPENPROVIDER_USER" ] || [ -z "$OPENPROVIDER_PASSWORDHASH" ]; then
    _err "You didn't specify the openprovider user and/or password hash."
    return 1
  fi

  # save the username and password to the account conf file.
  _saveaccountconf_mutable OPENPROVIDER_USER "$OPENPROVIDER_USER"
  _saveaccountconf_mutable OPENPROVIDER_PASSWORDHASH "$OPENPROVIDER_PASSWORDHASH"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain_name "$_domain_name"
  _debug _domain_extension "$_domain_extension"

  _debug "Getting current records"
  existing_items=""
  results_retrieved=0
  while true; do
    _openprovider_request "$(printf '<searchZoneRecordDnsRequest><name>%s.%s</name><offset>%s</offset></searchZoneRecordDnsRequest>' "$_domain_name" "$_domain_extension" "$results_retrieved")"

    items="$response"
    while true; do
      item="$(echo "$items" | _egrep_o '<openXML>.*<\/openXML>' | sed -n 's/.*\(<item>.*<\/item>\).*/\1/p')"
      _debug existing_items "$existing_items"
      _debug results_retrieved "$results_retrieved"
      _debug item "$item"

      if [ -z "$item" ]; then
        break
      fi

      items="$(echo "$items" | sed "s|${item}||")"

      results_retrieved="$(_math "$results_retrieved" + 1)"
      new_item="$(echo "$item" | sed -n 's/.*<item>.*\(<name>\(.*\)\.'"$_domain_name"'\.'"$_domain_extension"'<\/name>.*\(<type>.*<\/type>\).*\(<value>.*<\/value>\).*\(<prio>.*<\/prio>\).*\(<ttl>.*<\/ttl>\)\).*<\/item>.*/<item><name>\2<\/name>\3\4\5\6<\/item>/p')"
      if [ -z "$new_item" ]; then
        # Base record
        new_item="$(echo "$item" | sed -n 's/.*<item>.*\(<name>\(.*\)'"$_domain_name"'\.'"$_domain_extension"'<\/name>.*\(<type>.*<\/type>\).*\(<value>.*<\/value>\).*\(<prio>.*<\/prio>\).*\(<ttl>.*<\/ttl>\)\).*<\/item>.*/<item><name>\2<\/name>\3\4\5\6<\/item>/p')"
      fi

      if [ -z "$(echo "$new_item" | _egrep_o ".*<type>(A|AAAA|CNAME|MX|SPF|SRV|TXT|TLSA|SSHFP|CAA)<\/type>.*")" ]; then
        _debug "not an allowed record type, skipping" "$new_item"
        continue
      fi

      existing_items="$existing_items$new_item"
    done

    total="$(echo "$response" | _egrep_o '<total>.*?<\/total>' | sed -n 's/.*<total>\(.*\)<\/total>.*/\1/p')"

    _debug total "$total"
    if [ "$results_retrieved" -eq "$total" ]; then
      break
    fi
  done

  _debug "Creating acme record"
  acme_record="$(echo "$fulldomain" | sed -e "s/.$_domain_name.$_domain_extension$//")"
  _openprovider_request "$(printf '<modifyZoneDnsRequest><domain><name>%s</name><extension>%s</extension></domain><type>master</type><records><array>%s<item><name>%s</name><type>TXT</type><value>%s</value><ttl>86400</ttl></item></array></records></modifyZoneDnsRequest>' "$_domain_name" "$_domain_extension" "$existing_items" "$acme_record" "$txtvalue")"

  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_openprovider_rm() {
  fulldomain="$1"
  txtvalue="$2"

  OPENPROVIDER_USER="${OPENPROVIDER_USER:-$(_readaccountconf_mutable OPENPROVIDER_USER)}"
  OPENPROVIDER_PASSWORDHASH="${OPENPROVIDER_PASSWORDHASH:-$(_readaccountconf_mutable OPENPROVIDER_PASSWORDHASH)}"

  if [ -z "$OPENPROVIDER_USER" ] || [ -z "$OPENPROVIDER_PASSWORDHASH" ]; then
    _err "You didn't specify the openprovider user and/or password hash."
    return 1
  fi

  # save the username and password to the account conf file.
  _saveaccountconf_mutable OPENPROVIDER_USER "$OPENPROVIDER_USER"
  _saveaccountconf_mutable OPENPROVIDER_PASSWORDHASH "$OPENPROVIDER_PASSWORDHASH"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain_name "$_domain_name"
  _debug _domain_extension "$_domain_extension"

  _debug "Getting current records"
  existing_items=""
  results_retrieved=0
  while true; do
    _openprovider_request "$(printf '<searchZoneRecordDnsRequest><name>%s.%s</name><offset>%s</offset></searchZoneRecordDnsRequest>' "$_domain_name" "$_domain_extension" "$results_retrieved")"

    # Remove acme records from items
    items="$response"
    while true; do
      item="$(echo "$items" | _egrep_o '<openXML>.*<\/openXML>' | sed -n 's/.*\(<item>.*<\/item>\).*/\1/p')"
      _debug existing_items "$existing_items"
      _debug results_retrieved "$results_retrieved"
      _debug item "$item"

      if [ -z "$item" ]; then
        break
      fi

      items="$(echo "$items" | sed "s|${item}||")"

      results_retrieved="$(_math "$results_retrieved" + 1)"
      if ! echo "$item" | grep -v "$fulldomain"; then
        _debug "acme record, skipping" "$item"
        continue
      fi

      new_item="$(echo "$item" | sed -n 's/.*<item>.*\(<name>\(.*\)\.'"$_domain_name"'\.'"$_domain_extension"'<\/name>.*\(<type>.*<\/type>\).*\(<value>.*<\/value>\).*\(<prio>.*<\/prio>\).*\(<ttl>.*<\/ttl>\)\).*<\/item>.*/<item><name>\2<\/name>\3\4\5\6<\/item>/p')"

      if [ -z "$new_item" ]; then
        # Base record
        new_item="$(echo "$item" | sed -n 's/.*<item>.*\(<name>\(.*\)'"$_domain_name"'\.'"$_domain_extension"'<\/name>.*\(<type>.*<\/type>\).*\(<value>.*<\/value>\).*\(<prio>.*<\/prio>\).*\(<ttl>.*<\/ttl>\)\).*<\/item>.*/<item><name>\2<\/name>\3\4\5\6<\/item>/p')"
      fi

      if [ -z "$(echo "$new_item" | _egrep_o ".*<type>(A|AAAA|CNAME|MX|SPF|SRV|TXT|TLSA|SSHFP|CAA)<\/type>.*")" ]; then
        _debug "not an allowed record type, skipping" "$new_item"
        continue
      fi

      existing_items="$existing_items$new_item"
    done

    total="$(echo "$response" | _egrep_o '<total>.*?<\/total>' | sed -n 's/.*<total>\(.*\)<\/total>.*/\1/p')"

    _debug total "$total"

    if [ "$results_retrieved" -eq "$total" ]; then
      break
    fi
  done

  _debug "Removing acme record"
  _openprovider_request "$(printf '<modifyZoneDnsRequest><domain><name>%s</name><extension>%s</extension></domain><type>master</type><records><array>%s</array></records></modifyZoneDnsRequest>' "$_domain_name" "$_domain_extension" "$existing_items")"

  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _domain_name=domain
# _domain_extension=com
_get_root() {
  domain=$1
  i=2

  results_retrieved=0
  while true; do
    h=$(echo "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _openprovider_request "$(printf '<searchDomainRequest><domainNamePattern>%s</domainNamePattern><offset>%s</offset></searchDomainRequest>' "$(echo "$h" | cut -d . -f 1)" "$results_retrieved")"

    items="$response"
    while true; do
      item="$(echo "$items" | _egrep_o '<openXML>.*<\/openXML>' | sed -n 's/.*\(<domain>.*<\/domain>\).*/\1/p')"
      _debug existing_items "$existing_items"
      _debug results_retrieved "$results_retrieved"
      _debug item "$item"

      if [ -z "$item" ]; then
        break
      fi

      items="$(echo "$items" | sed "s|${item}||")"

      results_retrieved="$(_math "$results_retrieved" + 1)"

      _domain_name="$(echo "$item" | sed -n 's/.*<domain>.*<name>\(.*\)<\/name>.*<\/domain>.*/\1/p')"
      _domain_extension="$(echo "$item" | sed -n 's/.*<domain>.*<extension>\(.*\)<\/extension>.*<\/domain>.*/\1/p')"
      _debug _domain_name "$_domain_name"
      _debug _domain_extension "$_domain_extension"
      if [ "$_domain_name.$_domain_extension" = "$h" ]; then
        return 0
      fi
    done

    total="$(echo "$response" | _egrep_o '<total>.*?<\/total>' | sed -n 's/.*<total>\(.*\)<\/total>.*/\1/p')"

    _debug total "$total"

    if [ "$results_retrieved" -eq "$total" ]; then
      results_retrieved=0
      i="$(_math "$i" + 1)"
    fi
  done
  return 1
}

_openprovider_request() {
  request_xml=$1

  xml_prefix='<?xml version="1.0" encoding="UTF-8"?>'
  xml_content=$(printf '<openXML><credentials><username>%s</username><hash>%s</hash></credentials>%s</openXML>' "$OPENPROVIDER_USER" "$OPENPROVIDER_PASSWORDHASH" "$request_xml")
  response="$(_post "$(echo "$xml_prefix$xml_content" | tr -d '\n')" "$OPENPROVIDER_API" "" "POST" "application/xml")"
  _debug response "$response"
  if ! _contains "$response" "<openXML><reply><code>0</code>.*</reply></openXML>"; then
    _err "API request failed."
    return 1
  fi
}
