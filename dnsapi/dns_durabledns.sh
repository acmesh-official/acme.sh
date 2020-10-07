#!/usr/bin/env sh

#DD_API_User="xxxxx"
#DD_API_Key="xxxxxx"

_DD_BASE="https://durabledns.com/services/dns"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_durabledns_add() {
  fulldomain=$1
  txtvalue=$2

  DD_API_User="${DD_API_User:-$(_readaccountconf_mutable DD_API_User)}"
  DD_API_Key="${DD_API_Key:-$(_readaccountconf_mutable DD_API_Key)}"
  if [ -z "$DD_API_User" ] || [ -z "$DD_API_Key" ]; then
    DD_API_User=""
    DD_API_Key=""
    _err "You didn't specify a durabledns api user or key yet."
    _err "You can get yours from here https://durabledns.com/dashboard/index.php"
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable DD_API_User "$DD_API_User"
  _saveaccountconf_mutable DD_API_Key "$DD_API_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _dd_soap createRecord string zonename "$_domain." string name "$_sub_domain" string type "TXT" string data "$txtvalue" int aux 0 int ttl 10 string ddns_enabled N
  _contains "$response" "createRecordResponse"
}

dns_durabledns_rm() {
  fulldomain=$1
  txtvalue=$2

  DD_API_User="${DD_API_User:-$(_readaccountconf_mutable DD_API_User)}"
  DD_API_Key="${DD_API_Key:-$(_readaccountconf_mutable DD_API_Key)}"
  if [ -z "$DD_API_User" ] || [ -z "$DD_API_Key" ]; then
    DD_API_User=""
    DD_API_Key=""
    _err "You didn't specify a durabledns api user or key yet."
    _err "You can get yours from here https://durabledns.com/dashboard/index.php"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Find record id"
  if ! _dd_soap listRecords string zonename "$_domain."; then
    _err "can not listRecords"
    return 1
  fi

  subtxt="$(echo "$txtvalue" | cut -c 1-30)"
  record="$(echo "$response" | sed 's/<item\>/#<item>/g' | tr '#' '\n' | grep ">$subtxt")"
  _debug record "$record"
  if [ -z "$record" ]; then
    _err "can not find record for txtvalue" "$txtvalue"
    _err "$response"
    return 1
  fi

  recordid="$(echo "$record" | _egrep_o '<id xsi:type="xsd:int">[0-9]*</id>' | cut -d '>' -f 2 | cut -d '<' -f 1)"
  _debug recordid "$recordid"
  if [ -z "$recordid" ]; then
    _err "can not find record id"
    return 1
  fi

  if ! _dd_soap deleteRecord string zonename "$_domain." int id "$recordid"; then
    _err "delete error"
    return 1
  fi

  _contains "$response" "Success"
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  if ! _dd_soap "listZones"; then
    return 1
  fi

  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" ">$h.</origin>"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1

}

#method
_dd_soap() {
  _method="$1"
  shift
  _urn="${_method}wsdl"
  # put the parameters to xml
  body="<tns:$_method>
      <apiuser xsi:type=\"xsd:string\">$DD_API_User</apiuser>
      <apikey xsi:type=\"xsd:string\">$DD_API_Key</apikey>
    "
  while [ "$1" ]; do
    _t="$1"
    shift
    _k="$1"
    shift
    _v="$1"
    shift
    body="$body<$_k xsi:type=\"xsd:$_t\">$_v</$_k>"
  done
  body="$body</tns:$_method>"
  _debug2 "SOAP request ${body}"

  # build SOAP XML
  _xml='<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/"
xmlns:tns="urn:'$_urn'"
xmlns:types="urn:'$_urn'/encodedTypes"
xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <soap:Body soap:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'"$body"'</soap:Body>
</soap:Envelope>'

  _debug2 _xml "$_xml"
  # set SOAP headers
  _action="SOAPAction: \"urn:$_urn#$_method\""
  _debug2 "_action" "$_action"
  export _H1="$_action"
  export _H2="Content-Type: text/xml; charset=utf-8"

  _url="$_DD_BASE/$_method.php"
  _debug "_url" "$_url"
  if ! response="$(_post "${_xml}" "${_url}")"; then
    _err "Error <$1>"
    return 1
  fi
  _debug2 "response" "$response"
  response="$(echo "$response" | tr -d "\r\n" | _egrep_o ":${_method}Response .*:${_method}Response><")"
  _debug2 "response" "$response"
  return 0
}
