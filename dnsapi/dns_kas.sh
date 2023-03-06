#!/usr/bin/env sh
########################################################################
# All-inkl Kasserver hook script for acme.sh
#
# Environment variables:
#
#  - $KAS_Login (Kasserver API login name)
#  - $KAS_Authtype (Kasserver API auth type. Default: plain)
#  - $KAS_Authdata (Kasserver API auth data.)
#
# Last update: squared GmbH <github@squaredgmbh.de>
# Credits:
# - dns_he.sh. Thanks a lot man!
# - Martin Kammerlander, Phlegx Systems OG <martin.kammerlander@phlegx.com>
# - Marc-Oliver Lange <git@die-lang.es>
# - https://github.com/o1oo11oo/kasapi.sh
########################################################################
KAS_Api_GET="$(_get "https://kasapi.kasserver.com/soap/wsdl/KasApi.wsdl")"
KAS_Api="$(echo "$KAS_Api_GET" | tr -d ' ' | grep -i "<soap:addresslocation=" | sed "s/='/\n/g" | grep -i "http" | sed "s/'\/>//g")"
_info "[KAS] -> API URL $KAS_Api"

KAS_Auth_GET="$(_get "https://kasapi.kasserver.com/soap/wsdl/KasAuth.wsdl")"
KAS_Auth="$(echo "$KAS_Auth_GET" | tr -d ' ' | grep -i "<soap:addresslocation=" | sed "s/='/\n/g" | grep -i "http" | sed "s/'\/>//g")"
_info "[KAS] -> AUTH URL $KAS_Auth"

KAS_default_ratelimit=5 # TODO - Every response delivers a ratelimit (seconds) where KASAPI is blocking a request.

########  Public functions  #####################
dns_kas_add() {
  _fulldomain=$1
  _txtvalue=$2

  _info "[KAS] -> Using DNS-01 All-inkl/Kasserver hook"
  _info "[KAS] -> Check and Save Props"
  _check_and_save

  _info "[KAS] -> Adding $_fulldomain DNS TXT entry on all-inkl.com/Kasserver"
  _info "[KAS] -> Retriving Credential Token"
  _get_credential_token

  _info "[KAS] -> Checking Zone and Record_Name"
  _get_zone_and_record_name "$_fulldomain"

  _info "[KAS] -> Checking for existing Record entries"
  _get_record_id

  # If there is a record_id, delete the entry
  if [ -n "$_record_id" ]; then
    _info "[KAS] -> Existing records found. Now deleting old entries"
    for i in $_record_id; do
      _delete_RecordByID "$i"
    done
  else
    _info "[KAS] -> No record found."
  fi

  _info "[KAS] -> Creating TXT DNS record"
  action="add_dns_settings"
  kasReqParam="\"record_name\":\"$_record_name\""
  kasReqParam="$kasReqParam,\"record_type\":\"TXT\""
  kasReqParam="$kasReqParam,\"record_data\":\"$_txtvalue\""
  kasReqParam="$kasReqParam,\"record_aux\":\"0\""
  kasReqParam="$kasReqParam,\"zone_host\":\"$_zone\""
  response="$(_callAPI "$action" "$kasReqParam")"
  _debug2 "[KAS] -> Response" "$response"

  if [ -z "$response" ]; then
    _info "[KAS] -> Response was empty, please check manually."
    return 1
  elif _contains "$response" "<SOAP-ENV:Fault>"; then
    faultstring="$(echo "$response" | tr -d '\n\r' | sed "s/<faultstring>/\n=> /g" | sed "s/<\/faultstring>/\n/g" | grep "=>" | sed "s/=> //g")"
    case "${faultstring}" in
    "record_already_exists")
      _info "[KAS] -> The record already exists, which must not be a problem. Please check manually."
      ;;
    *)
      _err "[KAS] -> An error =>$faultstring<= occurred, please check manually."
      return 1
      ;;
    esac
  elif ! _contains "$response" "<item><key xsi:type=\"xsd:string\">ReturnString</key><value xsi:type=\"xsd:string\">TRUE</value></item>"; then
    _err "[KAS] -> An unknown error occurred, please check manually."
    return 1
  fi
  return 0
}

dns_kas_rm() {
  _fulldomain=$1
  _txtvalue=$2

  _info "[KAS] -> Using DNS-01 All-inkl/Kasserver hook"
  _info "[KAS] -> Check and Save Props"
  _check_and_save

  _info "[KAS] -> Cleaning up after All-inkl/Kasserver hook"
  _info "[KAS] -> Removing $_fulldomain DNS TXT entry on All-inkl/Kasserver"
  _info "[KAS] -> Retriving Credential Token"
  _get_credential_token

  _info "[KAS] -> Checking Zone and Record_Name"
  _get_zone_and_record_name "$_fulldomain"

  _info "[KAS] -> Getting Record ID"
  _get_record_id

  _info "[KAS] -> Removing entries with ID: $_record_id"
  # If there is a record_id, delete the entry
  if [ -n "$_record_id" ]; then
    for i in $_record_id; do
      _delete_RecordByID "$i"
    done
  else # Cannot delete or unkown error
    _info "[KAS] -> No record_id found that can be deleted. Please check manually."
  fi
  return 0
}

########################## PRIVATE FUNCTIONS ###########################
# Delete Record ID
_delete_RecordByID() {
  recId=$1
  action="delete_dns_settings"
  kasReqParam="\"record_id\":\"$recId\""
  response="$(_callAPI "$action" "$kasReqParam")"
  _debug2 "[KAS] -> Response" "$response"

  if [ -z "$response" ]; then
    _info "[KAS] -> Response was empty, please check manually."
    return 1
  elif _contains "$response" "<SOAP-ENV:Fault>"; then
    faultstring="$(echo "$response" | tr -d '\n\r' | sed "s/<faultstring>/\n=> /g" | sed "s/<\/faultstring>/\n/g" | grep "=>" | sed "s/=> //g")"
    case "${faultstring}" in
    "record_id_not_found")
      _info "[KAS] -> The record was not found, which perhaps is not a problem. Please check manually."
      ;;
    *)
      _err "[KAS] -> An error =>$faultstring<= occurred, please check manually."
      return 1
      ;;
    esac
  elif ! _contains "$response" "<item><key xsi:type=\"xsd:string\">ReturnString</key><value xsi:type=\"xsd:string\">TRUE</value></item>"; then
    _err "[KAS] -> An unknown error occurred, please check manually."
    return 1
  fi
}
# Checks for the ENV variables and saves them
_check_and_save() {
  KAS_Login="${KAS_Login:-$(_readaccountconf_mutable KAS_Login)}"
  KAS_Authtype="${KAS_Authtype:-$(_readaccountconf_mutable KAS_Authtype)}"
  KAS_Authdata="${KAS_Authdata:-$(_readaccountconf_mutable KAS_Authdata)}"

  if [ -z "$KAS_Login" ] || [ -z "$KAS_Authtype" ] || [ -z "$KAS_Authdata" ]; then
    KAS_Login=
    KAS_Authtype=
    KAS_Authdata=
    _err "[KAS] -> No auth details provided. Please set user credentials using the \$KAS_Login, \$KAS_Authtype, and \$KAS_Authdata environment variables."
    return 1
  fi
  _saveaccountconf_mutable KAS_Login "$KAS_Login"
  _saveaccountconf_mutable KAS_Authtype "$KAS_Authtype"
  _saveaccountconf_mutable KAS_Authdata "$KAS_Authdata"
  return 0
}

# Gets back the base domain/zone and record name.
# See: https://github.com/Neilpang/acme.sh/wiki/DNS-API-Dev-Guide
_get_zone_and_record_name() {
  action="get_domains"
  response="$(_callAPI "$action")"
  _debug2 "[KAS] -> Response" "$response"

  if [ -z "$response" ]; then
    _info "[KAS] -> Response was empty, please check manually."
    return 1
  elif _contains "$response" "<SOAP-ENV:Fault>"; then
    faultstring="$(echo "$response" | tr -d '\n\r' | sed "s/<faultstring>/\n=> /g" | sed "s/<\/faultstring>/\n/g" | grep "=>" | sed "s/=> //g")"
    _err "[KAS] -> Either no domains were found or another error =>$faultstring<= occurred, please check manually."
    return 1
  fi

  zonen="$(echo "$response" | sed 's/<item>/\n/g' | sed -r 's/(.*<key xsi:type="xsd:string">domain_name<\/key><value xsi:type="xsd:string">)(.*)(<\/value.*)/\2/' | sed '/^</d')"
  domain="$1"
  temp_domain="$(echo "$1" | sed 's/\.$//')"
  rootzone="$domain"
  for i in $zonen; do
    l1=${#rootzone}
    l2=${#i}
    if _endswith "$domain" "$i" && [ "$l1" -ge "$l2" ]; then
      rootzone="$i"
    fi
  done
  _zone="${rootzone}."
  temp_record_name="$(echo "$temp_domain" | sed "s/$rootzone//g")"
  _record_name="$(echo "$temp_record_name" | sed 's/\.$//')"
  _debug "[KAS] -> Zone:" "$_zone"
  _debug "[KAS] -> Domain:" "$domain"
  _debug "[KAS] -> Record_Name:" "$_record_name"
  return 0
}

# Retrieve the DNS record ID
_get_record_id() {
  action="get_dns_settings"
  kasReqParam="\"zone_host\":\"$_zone\""
  response="$(_callAPI "$action" "$kasReqParam")"
  _debug2 "[KAS] -> Response" "$response"

  if [ -z "$response" ]; then
    _info "[KAS] -> Response was empty, please check manually."
    return 1
  elif _contains "$response" "<SOAP-ENV:Fault>"; then
    faultstring="$(echo "$response" | tr -d '\n\r' | sed "s/<faultstring>/\n=> /g" | sed "s/<\/faultstring>/\n/g" | grep "=>" | sed "s/=> //g")"
    _err "[KAS] -> Either no domains were found or another error =>$faultstring<= occurred, please check manually."
    return 1
  fi

  _record_id="$(echo "$response" | tr -d '\n\r' | sed "s/<item xsi:type=\"ns2:Map\">/\n/g" | grep -i "$_record_name" | grep -i ">TXT<" | sed "s/<item><key xsi:type=\"xsd:string\">record_id<\/key><value xsi:type=\"xsd:string\">/=>/g" | grep -i "$_txtvalue" | sed "s/<\/value><\/item>/\n/g" | grep "=>" | sed "s/=>//g")"
  _debug "[KAS] -> Record Id: " "$_record_id"
  return 0
}

# Retrieve credential token
_get_credential_token() {
  baseParamAuth="\"kas_login\":\"$KAS_Login\""
  baseParamAuth="$baseParamAuth,\"kas_auth_type\":\"$KAS_Authtype\""
  baseParamAuth="$baseParamAuth,\"kas_auth_data\":\"$KAS_Authdata\""
  baseParamAuth="$baseParamAuth,\"session_lifetime\":600"
  baseParamAuth="$baseParamAuth,\"session_update_lifetime\":\"Y\""

  data='<?xml version="1.0" encoding="UTF-8"?><SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns1="urn:xmethodsKasApiAuthentication" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><SOAP-ENV:Body><ns1:KasAuth><Params xsi:type="xsd:string">{'
  data="$data$baseParamAuth}</Params></ns1:KasAuth></SOAP-ENV:Body></SOAP-ENV:Envelope>"

  _debug "[KAS] -> Be friendly and wait $KAS_default_ratelimit seconds by default before calling KAS API."
  _sleep $KAS_default_ratelimit

  contentType="text/xml"
  export _H1="SOAPAction: urn:xmethodsKasApiAuthentication#KasAuth"
  response="$(_post "$data" "$KAS_Auth" "" "POST" "$contentType")"
  _debug2 "[KAS] -> Response" "$response"

  if [ -z "$response" ]; then
    _info "[KAS] -> Response was empty, please check manually."
    return 1
  elif _contains "$response" "<SOAP-ENV:Fault>"; then
    faultstring="$(echo "$response" | tr -d '\n\r' | sed "s/<faultstring>/\n=> /g" | sed "s/<\/faultstring>/\n/g" | grep "=>" | sed "s/=> //g")"
    _err "[KAS] -> Could not retrieve login token or antoher error =>$faultstring<= occurred, please check manually."
    return 1
  fi

  _credential_token="$(echo "$response" | tr '\n' ' ' | sed 's/.*return xsi:type="xsd:string">\(.*\)<\/return>/\1/' | sed 's/<\/ns1:KasAuthResponse\(.*\)Envelope>.*//')"
  _debug "[KAS] -> Credential Token: " "$_credential_token"
  return 0
}

_callAPI() {
  kasaction=$1
  kasReqParams=$2

  baseParamAuth="\"kas_login\":\"$KAS_Login\""
  baseParamAuth="$baseParamAuth,\"kas_auth_type\":\"session\""
  baseParamAuth="$baseParamAuth,\"kas_auth_data\":\"$_credential_token\""

  data='<?xml version="1.0" encoding="UTF-8"?><SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns1="urn:xmethodsKasApi" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><SOAP-ENV:Body><ns1:KasApi><Params xsi:type="xsd:string">{'
  data="$data$baseParamAuth,\"kas_action\":\"$kasaction\""
  if [ -n "$kasReqParams" ]; then
    data="$data,\"KasRequestParams\":{$kasReqParams}"
  fi
  data="$data}</Params></ns1:KasApi></SOAP-ENV:Body></SOAP-ENV:Envelope>"

  _debug2 "[KAS] -> Request" "$data"

  _debug "[KAS] -> Be friendly and wait $KAS_default_ratelimit seconds by default before calling KAS API."
  _sleep $KAS_default_ratelimit

  contentType="text/xml"
  export _H1="SOAPAction: urn:xmethodsKasApi#KasApi"
  response="$(_post "$data" "$KAS_Api" "" "POST" "$contentType")"
  _debug2 "[KAS] -> Response" "$response"
  echo "$response"
}
