#!/usr/bin/env sh

#Client ID
#Dynu_ClientId="0b71cae7-a099-4f6b-8ddf-94571cdb760d"
#
#Secret
#Dynu_Secret="aCUEY4BDCV45KI8CSIC3sp2LKQ9"
#
#Token
Dynu_Token=""
#
#Endpoint
Dynu_EndPoint="https://api.dynu.com/v2"
#
#Author: Dynu Systems, Inc.
#Report Bugs here: https://github.com/shar0119/acme.sh
#
########  Public functions #####################

#Usage: add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dynu_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$Dynu_ClientId" ] || [ -z "$Dynu_Secret" ]; then
    Dynu_ClientId=""
    Dynu_Secret=""
    _err "Dynu client id and secret is not specified."
    _err "Please create you API client id and secret and try again."
    return 1
  fi

  #save the client id and secret to the account conf file.
  _saveaccountconf Dynu_ClientId "$Dynu_ClientId"
  _saveaccountconf Dynu_Secret "$Dynu_Secret"

  if [ -z "$Dynu_Token" ]; then
    _info "Getting Dynu token."
    if ! _dynu_authentication; then
      _err "Can not get token."
    fi
  fi

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain."
    return 1
  fi

  _debug _node "$_node"
  _debug _domain_name "$_domain_name"

  _info "Creating TXT record."
  if ! _dynu_rest POST "dns/$dnsId/record" "{\"domainId\":\"$dnsId\",\"nodeName\":\"$_node\",\"recordType\":\"TXT\",\"textData\":\"$txtvalue\",\"state\":true,\"ttl\":90}"; then
    return 1
  fi

  if ! _contains "$response" "200"; then
    _err "Could not add TXT record."
    return 1
  fi

  return 0
}

#Usage: rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dynu_rm() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$Dynu_ClientId" ] || [ -z "$Dynu_Secret" ]; then
    Dynu_ClientId=""
    Dynu_Secret=""
    _err "Dynu client id and secret is not specified."
    _err "Please create you API client id and secret and try again."
    return 1
  fi

  #save the client id and secret to the account conf file.
  _saveaccountconf Dynu_ClientId "$Dynu_ClientId"
  _saveaccountconf Dynu_Secret "$Dynu_Secret"

  if [ -z "$Dynu_Token" ]; then
    _info "Getting Dynu token."
    if ! _dynu_authentication; then
      _err "Can not get token."
    fi
  fi

  _debug "Detect root zone."
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain."
    return 1
  fi

  _debug _node "$_node"
  _debug _domain_name "$_domain_name"

  _info "Checking for TXT record."
  if ! _get_recordid "$fulldomain" "$txtvalue"; then
    _err "Could not get TXT record id."
    return 1
  fi

  if [ "$_dns_record_id" = "" ]; then
    _err "TXT record not found."
    return 1
  fi

  _info "Removing TXT record."
  if ! _delete_txt_record "$_dns_record_id"; then
    _err "Could not remove TXT record $_dns_record_id."
  fi

  return 0
}

########  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _node=_acme-challenge.www
# _domain_name=domain.com
_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _dynu_rest GET "dns/getroot/$h"; then
      return 1
    fi

    if _contains "$response" "\"domainName\":\"$h\"" >/dev/null; then
      dnsId=$(printf "%s" "$response" | tr -d "{}" | cut -d , -f 2 | cut -d : -f 2)
      _domain_name=$h
      _node=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1

}

_get_recordid() {
  fulldomain=$1
  txtvalue=$2

  if ! _dynu_rest GET "dns/$dnsId/record"; then
    return 1
  fi

  if ! _contains "$response" "$txtvalue"; then
    _dns_record_id=0
    return 0
  fi

  _dns_record_id=$(printf "%s" "$response" | sed -e 's/[^{]*\({[^}]*}\)[^{]*/\1\n/g' | grep "\"textData\":\"$txtvalue\"" | sed -e 's/.*"id":\([^,]*\).*/\1/')
  return 0
}

_delete_txt_record() {
  _dns_record_id=$1

  if ! _dynu_rest DELETE "dns/$dnsId/record/$_dns_record_id"; then
    return 1
  fi

  if ! _contains "$response" "200"; then
    return 1
  fi

  return 0
}

_dynu_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Authorization: Bearer $Dynu_Token"
  export _H2="Content-Type: application/json"

  if [ "$data" ] || [ "$m" = "DELETE" ]; then
    _debug data "$data"
    response="$(_post "$data" "$Dynu_EndPoint/$ep" "" "$m")"
  else
    _info "Getting $Dynu_EndPoint/$ep"
    response="$(_get "$Dynu_EndPoint/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_dynu_authentication() {
  realm="$(printf "%s" "$Dynu_ClientId:$Dynu_Secret" | _base64)"

  export _H1="Authorization: Basic $realm"
  export _H2="Content-Type: application/json"

  response="$(_get "$Dynu_EndPoint/oauth2/token")"
  if [ "$?" != "0" ]; then
    _err "Authentication failed."
    return 1
  fi
  if _contains "$response" "Authentication Exception"; then
    _err "Authentication failed."
    return 1
  fi
  if _contains "$response" "access_token"; then
    Dynu_Token=$(printf "%s" "$response" | tr -d "{}" | cut -d , -f 1 | cut -d : -f 2 | cut -d '"' -f 2)
  fi
  if _contains "$Dynu_Token" "null"; then
    Dynu_Token=""
  fi

  _debug2 response "$response"
  return 0
}
