#!/usr/bin/env sh

#This is a working API script to add a TXT record to the DNS Exit-managed DNS service.
# dns_myapi_add()
#Which will be called by acme.sh to add the txt record to th DNS Exit DNS service as part
#of the SSL certificate provisioning request.
#returns 0 means success, otherwise error.
#
#Author: John Berlet
#Date: 31/01/2022
#Report Bugs here: https://github.com/acmesh-official/acme.sh/issues/3925
#
########  Public functions #####################


dns_japi_add() {


  fulldomain=$1
  txtvalue=$2
  JAPIendpoint="https://api.dnsexit.com/dns/"
  JAPIdomain="${_domain}"
  #_debug "Domain being used with custom script is: $domain"
  fullchallengedomain="${JAPI_domain:-$(_readaccountconf_mutable JAPI_domain)}"
  _debug "Full Challenge Domain is: $fullchallengedomain"
  JAPI_apikey="${JAPI_apikey:-$(_readaccountconf_mutable JAPI_apikey)}"
  #$passedDomain=$_domain

  #Set H1,H2 headers with DNS Exit API key
  export _H1="Content-Type: application/json"
  export _H2="apikey: $JAPI_apikey"

  _debug "Defined apikey $JAPI_apikey"
  if [ -z "$JAPI_apikey" ] || [ -z "$fullchallengedomain" ]; then
    JAPI_apikey=""
    _info "You didn't specify the api key or the full zone domain name"
    _info "Please define --> 'export xxx' your api key and fully qualified zone and domain name"
    _info "Example: 'export JAPI_apikey=<your DNS Exit api key>'"
    _info "Cont: 'export JAPI_domain=<_acme-challenge.your domain name>'"
    return 1
  fi
 #Save DNS Exit account API/domain challenge zone/domain name in account.conf for future renewals
  _saveaccountconf_mutable JAPI_apikey "$JAPI_apikey"
  _saveaccountconf_mutable JAPI_domain "$JAPI_domain"


  _debug "First detect the root zone"
  _debug "Calling DNS Exit DNS API..."
  _info "Using JAPI"
  _debug "Passed domain to function: $fulldomain"
  _debug "Full Challenge domain: $fullchallengedomain"
  _debug txtvalue "$txtvalue"
  #_debug _domain_id "$_domain_id"
  #_debug _sub_domain "$_sub_domain"
  #_debug _domain "$_domain"
  #_err "Not implemented!"

 response="$(_post "{\"domain\":\"$JAPIdomain\",\"update\": {\"type\":\"TXT\",\"name\":\"$fullchallengedomain\",\"content\":\"$txtvalue\",\"ttl\":0}}" $JAPIendpoint "" POST "application/json")"  
   if ! printf "%s" "$response" | grep \"code\":0>/dev/null; then
    _err "There was an error updating the TXT record..."
    _err "DNS Exit API response: $response"
    _err "Please refer to this site for additional information related to this error code - https://dnsexit.com/dns/dns-api/"
    return 1
  fi
  return 0
}
#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_japi_rm() {
  fulldomain=$1
  txtvalue=$2
  JAPIendpoint="https://api.dnsexit.com/dns/"
  JAPIdomain="${_domain}"
  #_debug "Domain being used with custom script is: $domain"
  fullchallengedomain="${JAPI_domain:-$(_readaccountconf_mutable JAPI_domain)}"
  _debug "Full Challenge Domain is: $fullchallengedomain"
  JAPI_apikey="${JAPI_apikey:-$(_readaccountconf_mutable JAPI_apikey)}"
  #Set H1,H2 headers with DNS Exit API key
  export _H1="Content-Type: application/json"
  export _H2="apikey: $JAPI_apikey"
  #domainUpdate=$domain
  _debug "Defined apikey $JAPI_apikey"
  if [ -z "$JAPI_apikey" ] || [ -z "$fullchallengedomain" ]; then
    JAPI_apikey=""
    _info "You didn't specify the api key or the full zone domain name for the TXT record removal"
    _info "Please define --> 'export xxx' your api key and fully qualified zone and domain name"
    _info "Example: 'export JAPI_apikey=<your DNS Exit api key>'"
    _info "Cont: 'export JAPI_domain=<_acme-challenge.your domain name>'"
    return 1
  fi
  _debug "First detect the root zone"
  _debug "Calling DNS Exit DNS API..."
  _info "Using JAPI"
  _debug "Passed domain to function: $fulldomain"
  _debug "Full Challenge domain: $fullchallengedomain"
  _debug txtvalue "$txtvalue"
  #_debug _domain_id "$_domain_id"
  #_debug _sub_domain "$_sub_domain"
  #_debug _domain "$_domain"
  #_err "Not implemented!"

 response="$(_post "{\"domain\":\"$JAPIdomain\",\"delete\": {\"type\":\"TXT\",\"name\":\"$fullchallengedomain\",\"content\":\"$txtvalue\",\"ttl\":0}}" $JAPIendpoint "" POST "application/json")"  
   if ! printf "%s" "$response" | grep \"code\":0>/dev/null; then
    _err "There was an error deleting the TXT record..."
    _err "DNS Exit API response: $response"
    _err "Please refer to this site for additional information related to this error code - https://dnsexit.com/dns/dns-api/"
    return 1
  fi
  return 0

  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
}
