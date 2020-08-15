#!/usr/bin/env sh

#######################################################
#
# easyDNS REST API for acme.sh by Neilpang based on dns_cf.sh
# 
# API Documentation: https://sandbox.rest.easydns.net:3001/
#
# Author: wurzelpanzer [wurzelpanzer@maximolider.net]
# Report Bugs here: https://github.com/acmesh-official/acme.sh/issues/2647
#
####################  Public functions #################

#EASYDNS_Key="xxxxxxxxxxxxxxxxxxxxxxxx"
#EASYDNS_Token="xxxxxxxxxxxxxxxxxxxxxxxx"
EASYDNS_Api="https://rest.easydns.net"

#Usage: add  _acme-challenge.www.domain.com  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_easydns_add() {
  fulldomain=$1
  txtvalue=$2

  EASYDNS_Token="${EASYDNS_Token:-$(_readaccountconf_mutable EASYDNS_Token)}"
  EASYDNS_Key="${EASYDNS_Key:-$(_readaccountconf_mutable EASYDNS_Key)}"

  if [ -z "$EASYDNS_Token" ] || [ -z "$EASYDNS_Key" ]; then
    _err "You didn't specify an easydns.net token or api key. Signup at https://cp.easydns.com/manage/security/api/signup.php"
    return 1
  else
    _saveaccountconf_mutable EASYDNS_Token "$EASYDNS_Token"
    _saveaccountconf_mutable EASYDNS_Key "$EASYDNS_Key"
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _EASYDNS_rest GET "zones/records/all/${_domain}/search/${_sub_domain}"

  if ! printf "%s" "$response" | grep \"status\":200 >/dev/null; then
    _err "Error"
    return 1
  fi

  _info "Adding record"
  if _EASYDNS_rest PUT "zones/records/add/$_domain/TXT" "{\"host\":\"$_sub_domain\",\"rdata\":\"$txtvalue\"}"; then
    if _contains "$response" "\"status\":201"; then
      _info "Added, OK"
      return 0
    elif _contains "$response" "Record already exists"; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1

}

dns_easydns_rm() {
  fulldomain=$1
  txtvalue=$2

  EASYDNS_Token="${EASYDNS_Token:-$(_readaccountconf_mutable EASYDNS_Token)}"
  EASYDNS_Key="${EASYDNS_Key:-$(_readaccountconf_mutable EASYDNS_Key)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _EASYDNS_rest GET "zones/records/all/${_domain}/search/${_sub_domain}"

  if ! printf "%s" "$response" | grep \"status\":200 >/dev/null; then
    _err "Error"
    return 1
  fi

  count=$(printf "%s\n" "$response" | _egrep_o "\"count\":[^,]*" | cut -d : -f 2)
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    record_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | head -n 1)
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if ! _EASYDNS_rest DELETE "zones/records/$_domain/$record_id"; then
      _err "Delete record error."
      return 1
    fi
    _contains "$response" "\"status\":200"
  fi

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _EASYDNS_rest GET "zones/records/all/$h"; then
      return 1
    fi

    if _contains "$response" "\"status\":200"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_EASYDNS_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  basicauth=$(printf "%s" "$EASYDNS_Token":"$EASYDNS_Key" | _base64)

  export _H1="accept: application/json"
  if [ "$basicauth" ]; then
    export _H2="Authorization: Basic $basicauth"
  fi

  if [ "$m" != "GET" ]; then
    export _H3="Content-Type: application/json"
    _debug data "$data"
    response="$(_post "$data" "$EASYDNS_Api/$ep" "" "$m")"
  else
    response="$(_get "$EASYDNS_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
