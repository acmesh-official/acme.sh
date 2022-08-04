#!/usr/bin/env sh
########################################################################
# all-inkl.com Kasserver hook script for acme.sh
#
# Environment variables:
#
#  - $KAS_Login (Kasserver API login name)
#  - $KAS_Authtype (Kasserver API auth type. Default: sha1)
#  - $KAS_Authdata (Kasserver API auth data.)
#
# Author: squared GmbH <github@squaredgmbh.de>
# Credits:
# Inspired by dns_he.sh. Thanks a lot man!
# Previous version by Martin Kammerlander, Phlegx Systems OG <martin.kammerlander@phlegx.com>
# Previous update by Marc-Oliver Lange <git@die-lang.es>
# KASAPI SOAP guideline by https://github.com/o1oo11oo/kasapi.sh
########################################################################
KAS_Api_GET="$(_get "https://kasapi.kasserver.com/soap/wsdl/KasApi.wsdl")"
KAS_Api="$(echo "$KAS_Api_GET" | tr -d ' ' | grep -i "<soap:addresslocation=" | sed "s/='/\n/g" | grep -i "http" | sed "s/'\/>//g")"
_info "##KAS## Using $KAS_Api"
KAS_default_ratelimit=5 # TODO - Every response delivers a ratelimit (seconds) where KASAPI is blocking a request.
########  Public functions  #####################
dns_kas_add() {
  _fulldomain=$1
  _txtvalue=$2
  _info "##KAS## Using DNS-01 All-inkl/Kasserver hook"
  _info "##KAS## Adding $_fulldomain DNS TXT entry on All-inkl/Kasserver"
  _info "##KAS## Check and Save Props"
  _check_and_save
  _info "##KAS## Checking Zone and Record_Name"
  _get_zone_and_record_name "$_fulldomain"
  _info "##KAS## Getting Record ID"
  _get_record_id

  _info "##KAS## Creating TXT DNS record"

  params_request="\"record_name\":\"$_record_name\""
  params_request="$params_request,\"record_type\":\"TXT\""
  params_request="$params_request,\"record_data\":\"$_txtvalue\""
  params_request="$params_request,\"record_aux\":\"0\""
  params_request="$params_request,\"zone_host\":\"$_zone\""

  response="$(_post_soap "add_dns_settings" "$params_request")"

  if [ -z "$response" ]; then
    _info "##KAS## Response was empty, please check manually."
    return 1
  elif _contains "$response" "<SOAP-ENV:Fault>"; then
    faultstring="$(echo "$response" | tr -d '\n\r' | sed "s/<faultstring>/\n=> /g" | sed "s/<\/faultstring>/\n/g" | grep "=>" | sed "s/=> //g")"
    case "${faultstring}" in
    "record_already_exists")
      _info "##KAS## The record already exists, which must not be a problem. Please check manually."
      ;;
    *)
      _err "##KAS## An error =>$faultstring<= occurred, please check manually."
      return 1
      ;;
    esac
  elif ! _contains "$response" "<item><key xsi:type=\"xsd:string\">ReturnString</key><value xsi:type=\"xsd:string\">TRUE</value></item>"; then
    _err "##KAS## An unknown error occurred, please check manually."
    return 1
  fi
  return 0
}

dns_kas_rm() {
  _fulldomain=$1
  _txtvalue=$2
  _info "##KAS## Using DNS-01 All-inkl/Kasserver hook"
  _info "##KAS## Cleaning up after All-inkl/Kasserver hook"
  _info "##KAS## Removing $_fulldomain DNS TXT entry on All-inkl/Kasserver"
  _info "##KAS## Check and Save Props"
  _check_and_save
  _info "##KAS## Checking Zone and Record_Name"
  _get_zone_and_record_name "$_fulldomain"
  _info "##KAS## Getting Record ID"
  _get_record_id

  if [ -n "$_record_id" ]; then
    for i in $_record_id; do
      _info "##KAS## Removing $_record_id"
      params_request="\"record_id\":\"$_record_id\""

      response="$(_post_soap "delete_dns_settings" "$params_request")"

      if [ -z "$response" ]; then
        _info "##KAS## Response was empty, please check manually."
        return 1
      elif _contains "$response" "<SOAP-ENV:Fault>"; then
        faultstring="$(echo "$response" | tr -d '\n\r' | sed "s/<faultstring>/\n=> /g" | sed "s/<\/faultstring>/\n/g" | grep "=>" | sed "s/=> //g")"
        case "${faultstring}" in
        "record_id_not_found")
          _info "##KAS## The record was not found, which must not be a problem. Please check manually."
          ;;
        *)
          _err "##KAS## An error =>$faultstring<= occurred, please check manually."
          return 1
          ;;
        esac
      elif ! _contains "$response" "<item><key xsi:type=\"xsd:string\">ReturnString</key><value xsi:type=\"xsd:string\">TRUE</value></item>"; then
        _err "##KAS## An unknown error occurred, please check manually."
        return 1
      fi
    done
  else
    _info "##KAS## No records where found, which must not be a problem. Please check manually."
  fi
  return 0
}

########################## PRIVATE FUNCTIONS ###########################

# Checks for the ENV variables and saves them
_check_and_save() {
  KAS_Login="${KAS_Login:-$(_readaccountconf_mutable KAS_Login)}"
  KAS_Authtype="${KAS_Authtype:-$(_readaccountconf_mutable KAS_Authtype)}"
  KAS_Authdata="${KAS_Authdata:-$(_readaccountconf_mutable KAS_Authdata)}"

  if [ -z "$KAS_Login" ] || [ -z "$KAS_Authtype" ] || [ -z "$KAS_Authdata" ]; then
    KAS_Login=
    KAS_Authtype=
    KAS_Authdata=
    _err "##KAS## No auth details provided. Please set user credentials using the \$KAS_Login, \$KAS_Authtype, and \$KAS_Authdata environment variables."
    return 1
  fi
  _saveaccountconf_mutable KAS_Login "$KAS_Login"
  _saveaccountconf_mutable KAS_Authtype "$KAS_Authtype"
  _saveaccountconf_mutable KAS_Authdata "$KAS_Authdata"
  return 0
}

# Gets back the base domain/zone and record name.
# See: https://github.com/acmesh-official/acme.sh/wiki/DNS-API-Dev-Guide
_get_zone_and_record_name() {
  _info "##KAS## Get domain info"

  response="$(_post_soap "get_domains")"

  if [ -z "$response" ]; then
    _info "##KAS## Response was empty, please check manually."
    return 1
  elif _contains "$response" "<SOAP-ENV:Fault>"; then
    faultstring="$(echo "$response" | tr -d '\n\r' | sed "s/<faultstring>/\n=> /g" | sed "s/<\/faultstring>/\n/g" | grep "=>" | sed "s/=> //g")"
    _err "##KAS## Either no domains were found or another error =>$faultstring<= occurred, please check manually."
    return 1
  fi

  _zonen="$(echo "$response" | tr -d '\n\r' | sed "s/<item xsi:type=\"ns2:Map\">/\n/g" | sed "s/<item><key xsi:type=\"xsd:string\">domain_name<\/key><value xsi:type=\"xsd:string\">/=> /g" | sed "s/<\/value><\/item>/\n/g" | grep "=>" | sed "s/=> //g")"
  _domain="$1"
  _temp_domain="$(echo "$1" | sed 's/\.$//')"
  _rootzone="$_domain"
  for i in $_zonen; do
    l1=${#_rootzone}
    l2=${#i}
    if _endswith "$_domain" "$i" && [ "$l1" -ge "$l2" ]; then
      _rootzone="$i"
    fi
  done
  _zone="${_rootzone}."
  _temp_record_name="$(echo "$_temp_domain" | sed "s/$_rootzone//g")"
  _record_name="$(echo "$_temp_record_name" | sed 's/\.$//')"
  _debug2 "##KAS## Zone:" "$_zone"
  _debug2 "##KAS## Domain:" "$_domain"
  _debug2 "##KAS## Record_Name:" "$_record_name"
  return 0
}

# Retrieve the DNS record ID
_get_record_id() {
  _info "##KAS## Get domain info"

  params_request="\"zone_host\":\"$_zone\""

  response="$(_post_soap "get_dns_settings" "$params_request")"

  if [ -z "$response" ]; then
    _info "##KAS## Response was empty, please check manually."
    return 1
  elif _contains "$response" "<SOAP-ENV:Fault>"; then
    faultstring="$(echo "$response" | tr -d '\n\r' | sed "s/<faultstring>/\n=> /g" | sed "s/<\/faultstring>/\n/g" | grep "=>" | sed "s/=> //g")"
    _err "##KAS## Either no domains were found or another error =>$faultstring<= occurred, please check manually."
    return 1
  fi

  _record_id="$(echo "$response" | tr -d '\n\r' | sed "s/<item xsi:type=\"ns2:Map\">/\n/g" | grep -i "$_record_name" | grep -i ">TXT<" | sed "s/<item><key xsi:type=\"xsd:string\">record_id<\/key><value xsi:type=\"xsd:string\">/=>/g" | sed "s/<\/value><\/item>/\n/g" | grep "=>" | sed "s/=>//g")"
  _debug2 _record_id "$_record_id"
  return 0
}

_post_soap() {
  KAS_Action=$1
  KAS_Params=$2

  export _H1="SOAPAction: \"urn:xmethodsKasApi#KasApi\""

  params_auth="\"kas_login\":\"$KAS_Login\""
  params_auth="$params_auth,\"kas_auth_type\":\"$KAS_Authtype\""
  params_auth="$params_auth,\"kas_auth_data\":\"$KAS_Authdata\""

  data='<?xml version="1.0" encoding="UTF-8"?><SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns1="urn:xmethodsKasApi" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><SOAP-ENV:Body><ns1:KasApi><Params xsi:type="xsd:string">{'
  data="$data$params_auth,\"kas_action\":\"$KAS_Action\""
  if [ -n "$KAS_Params" ]; then
    data="$data,\"KasRequestParams\":{$KAS_Params}"
  fi
  data="$data}</Params></ns1:KasApi></SOAP-ENV:Body></SOAP-ENV:Envelope>"

  _debug2 "##KAS## Wait for $KAS_default_ratelimit seconds by default before calling KAS API."
  _sleep $KAS_default_ratelimit

  response="$(_post "$data" "$KAS_Api" "" "POST" "text/xml")"
  _debug2 "##KAS## response" "$response"

  echo "$response"
}
