#!/usr/bin/env sh

#Secret
#FastVps_Secret="2323f891ghfhf57480f923a3031d49gfdg94ca2768ea443f8262d6f78851379d5a6"
#

#Token
FastVps_Token=""
#

#Endpoint
FastVps_EndPoint="https://fastdns.fv.ee"
#

#Author: Voinkov Andrey.
#Report Bugs here: https://github.com/exzm/acme.sh
#

########  Public functions #####################

#Usage: add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_fastvps_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$FastVps_Secret" ]; then
    FastVps_Secret=""
    _err "FastVps secret is not specified."
    _err "Please create secret https://bill2fast.com/dns and try again."
    return 1
  fi

  #save the secret to the account conf file.
  _saveaccountconf FastVps_Secret "$FastVps_Secret"

  if [ -z "$FastVps_Token" ]; then
    _info "Getting FastVps token."
    if ! _fastvps_authentication; then
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
  if ! _fastvps_rest POST "api/domains/$dnsId/records" "{\"name\":\"$_node\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"ttl\":90}"; then
    return 1
  fi

  if _contains "$response" "errors"; then
    _err "Could not add TXT record."
    return 1
  fi

  return 0
}

#Usage: rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_fastvps_rm() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$FastVps_Secret" ]; then
    FastVps_Secret=""
    _err "Please create you API secret and try again."
    return 1
  fi

  #save the secret to the account conf file.
  _saveaccountconf FastVps_Secret "$FastVps_Secret"

  if [ -z "$FastVps_Token" ]; then
    _info "Getting FastVps token."
    if ! _fastvps_authentication; then
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

    if ! _fastvps_rest GET "api/domains/$h/name"; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\"" >/dev/null; then
      dnsId=$(printf "%s" "$response" | grep -Po '(?<="id":)[^,"\\]*(?:\\.[^"\\]*)*')
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

  if ! _fastvps_rest GET "api/domains/$dnsId/records"; then
    return 1
  fi

  if ! _contains "$response" "$txtvalue"; then
    _dns_record_id=0
    return 0
  fi

  _dns_record_id=$(printf "%s" "$response" | sed -e 's/[^{]*\({[^}]*}\)[^{]*/\1\n/g' | grep "\"content\":\"$txtvalue\"" | sed -e 's/.*"id":"\([^",]*\).*/\1/')
  return 0
}

_delete_txt_record() {
  _dns_record_id=$1

  if ! _fastvps_rest DELETE "/api/domains/$dnsId/records/$_dns_record_id"; then
    return 1
  fi

  if _contains "$response" "errors"; then
    return 1
  fi

  return 0
}

_fastvps_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Authorization: Bearer $FastVps_Token"
  export _H2="Content-Type: application/json"

  if [ "$data" ] || [ "$m" = "DELETE" ]; then
    _debug data "$data"
    response="$(_post "$data" "$FastVps_EndPoint/$ep" "" "$m")"
  else
    _info "Getting $FastVps_EndPoint/$ep"
    response="$(_get "$FastVps_EndPoint/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_fastvps_authentication() {

  export _H1="Authenticate: $FastVps_Secret"
  export _H2="Content-Type: application/json"

  response="$(_post "" "$FastVps_EndPoint/login_token" "" "")"

  if [ "$?" != "0" ]; then
    _err "Authentication failed."
    return 1
  fi
  if _contains "$response" "token"; then
    FastVps_Token=$(printf "%s" "$response" | grep -Po '(?<="token":")[^"\\]*(?:\\.[^"\\]*)*')
  fi
  if _contains "$FastVps_Token" "null"; then
    FastVps_Token=""
  fi
  _info "Authentication success"

  _debug2 response "$response"
  return 0
}