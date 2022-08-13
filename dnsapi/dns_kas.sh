#!/usr/bin/env sh
########################################################################
# All-inkl Kasserver hook script for acme.sh
#
# Environment variables:
#
#  - $KAS_Login (Kasserver API login name)
#  - $KAS_Authtype (Kasserver API auth type. Default: sha1)
#  - $KAS_Authdata (Kasserver API auth data.)
#
# Author: Martin Kammerlander, Phlegx Systems OG <martin.kammerlander@phlegx.com>
# Updated by: Marc-Oliver Lange <git@die-lang.es>
# Credits: Inspired by dns_he.sh. Thanks a lot man!
# Git repo: https://github.com/phlegx/acme.sh
# TODO: Better Error handling
########################################################################
KAS_Api="https://kasapi.kasserver.com/soap/KasApi.php"
KAS_Auth="https://kasapi.kasserver.com/soap/KasAuth.php"
########  Public functions  #####################
dns_kas_add() {
  _fulldomain=$1
  _txtvalue=$2

  _info "### -> Using DNS-01 All-inkl/Kasserver hook"
  _info "### -> Adding $_fulldomain DNS TXT entry on All-inkl/Kasserver"
  _info "### -> Retriving Credential Token"
  _get_credential_token

  _info "### -> Check and Save Props"
  _check_and_save

  _info "### -> Checking Zone and Record_Name"
  _get_zone_and_record_name "$_fulldomain"

  _info "### -> Checking for existing Record entries"
  _get_record_id

  # If there is a record_id, delete the entry
  if [ -n "$_record_id" ]; then
    _info "Existing records found. Now deleting old entries"
    for i in $_record_id; do
      _delete_RecordByID "$i"
    done
  else
    _info "No record found."
  fi

  _info "### -> Creating TXT DNS record"
  action="add_dns_settings"
  kasReqParam="{\"record_name\":\"$_record_name\",\"record_type\":\"TXT\",\"record_data\":\"$_txtvalue\",\"record_aux\":\"0\",\"zone_host\":\"$_zone\"}"
  response="$(_callAPI "$action" "$kasReqParam")"

  _debug2 "Response" "$response"

  if ! _contains "$response" "TRUE"; then
    _err "An unkown error occurred, please check manually."
    return 1
  fi
  return 0
}

dns_kas_rm() {
  _fulldomain=$1
  _txtvalue=$2

  _info "### -> Using DNS-01 All-inkl/Kasserver hook"
  _info "### -> Cleaning up after All-inkl/Kasserver hook"
  _info "### -> Removing $_fulldomain DNS TXT entry on All-inkl/Kasserver"
  _info "### -> Retriving Credential Token"
  _get_credential_token

  _info "### -> Check and Save Props"
  _check_and_save

  _info "### -> Checking Zone and Record_Name"
  _get_zone_and_record_name "$_fulldomain"

  _info "### -> Getting Record ID"
  _get_record_id

  _info "### -> Removing entries with ID: $_record_id"
  # If there is a record_id, delete the entry
  if [ -n "$_record_id" ]; then
    for i in $_record_id; do
      _delete_RecordByID "$i"
    done
  else # Cannot delete or unkown error
    _info "No record_id found that can be deleted. Please check manually."
  fi
  return 0
}

########################## PRIVATE FUNCTIONS ###########################
# Delete Record ID
_delete_RecordByID() {
  recId=$1
  action="delete_dns_settings"
  kasReqParam="{\"record_id\":\"$recId\"}"
  response="$(_callAPI "$action" "$kasReqParam")"
  _debug2 "Response" "$response"
  if ! _contains "$response" "TRUE"; then
    _info "Either the txt record is not found or another error occurred, please check manually."
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
    _err "No auth details provided. Please set user credentials using the \$KAS_Login, \$KAS_Authtype, and \$KAS_Authdata environment variables."
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
  kasReqParam="[]"
  response="$(_callAPI "$action" "$kasReqParam")"
  _debug2 "Response" "$response"
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
  _debug "Zone:" "$_zone"
  _debug "Domain:" "$domain"
  _debug "Record_Name:" "$_record_name"
  return 0
}

# Retrieve the DNS record ID
_get_record_id() {
  action="get_dns_settings"
  kasReqParam="{\"zone_host\":\"$_zone\",\"nameserver\":\"ns5.kasserver.com\"}"
  response="$(_callAPI "$action" "$kasReqParam")"

  _debug2 "Response" "$response"
  _record_id="$(echo "$response" | sed 's/<item xsi:type="ns2:Map">/\n/g' | sed -n -e "/^.*$_record_name.*/Ip" | sed -n -e "/^.*$_txtvalue.*/Ip" | sed -r 's/(.*record_id<\/key><value xsi:type="xsd:string">)([0-9]+)(<\/value.*)/\2/')"
  _debug "Record Id: " "$_record_id"
  return 0
}

# Retrieve credential token
_get_credential_token() {
  data="<SOAP-ENV:Envelope xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:ns1=\"urn:xmethodsKasApiAuthentication\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:SOAP-ENC=\"http://schemas.xmlsoap.org/soap/encoding/\" SOAP-ENV:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><SOAP-ENV:Body><ns1:KasAuth>"
  data="$data<Params xsi:type=\"xsd:string\">{\"kas_login\":\"$KAS_Login\",\"kas_auth_type\":\"$KAS_Authtype\",\"kas_auth_data\":\"$KAS_Authdata\",\"session_lifetime\":600,\"session_update_lifetime\":\"Y\",\"session_2fa\":123456}</Params>"
  data="$data</ns1:KasAuth></SOAP-ENV:Body></SOAP-ENV:Envelope>"

  _debug "Be frindly and wait 10 seconds by default before calling KAS API."
  _sleep 10

  contentType="text/xml"
  export _H1="SOAPAction: ns1:KasAuth"
  response="$(_post "$data" "$KAS_Auth" "" "POST" "$contentType")"
  _debug2 "Response" "$response"

  _credential_token="$(echo "$response" | tr '\n' ' ' | sed 's/.*return xsi:type="xsd:string">\(.*\)<\/return>/\1/' | sed 's/<\/ns1:KasAuthResponse\(.*\)Envelope>.*//')"
  _debug "Credential Token: " "$_credential_token"
  return 0
}

_callAPI() {
  kasaction=$1
  kasReqParams=$2
  baseParam="<Params xsi:type=\"xsd:string\">{\"kas_login\":\"$KAS_Login\",\"kas_auth_type\":\"session\",\"kas_auth_data\":\"$_credential_token\",\"kas_action\":\"$kasaction\",\"KasRequestParams\":$kasReqParams"
  baseParamClosing="}</Params>"
  data="<SOAP-ENV:Envelope xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:ns1=\"urn:xmethodsKasApi\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:SOAP-ENC=\"http://schemas.xmlsoap.org/soap/encoding/\" SOAP-ENV:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><SOAP-ENV:Body><ns1:KasApi>"
  data="$data$baseParam$baseParamClosing"
  data="$data</ns1:KasApi></SOAP-ENV:Body></SOAP-ENV:Envelope>"
  _debug2 "Request" "$data"

  _debug "Be frindly and wait 10 seconds by default before calling KAS API."
  _sleep 10

  contentType="text/xml"
  export _H1="SOAPAction: ns1:KasApi"
  response="$(_post "$data" "$KAS_Api" "" "POST" "$contentType")"
  _debug2 "Response" "$response"
  echo "$response"
}
