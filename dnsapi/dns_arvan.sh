#!/usr/bin/env sh

#Arvan_Token="Apikey xxxx"

ARVAN_API_URL="https://napi.arvancloud.com/cdn/4.0/domains"
#Author: Vahid Fardi
#Report Bugs here: https://github.com/Neilpang/acme.sh
#
########  Public functions #####################

#Usage: dns_arvan_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_arvan_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using Arvan"

  Arvan_Token="${Arvan_Token:-$(_readaccountconf_mutable Arvan_Token)}"

  if [ -z "$Arvan_Token" ]; then
    _err "You didn't specify \"Arvan_Token\" token yet."
    _err "You can get yours from here https://npanel.arvancloud.com/profile/api-keys"
    return 1
  fi
  #save the api token to the account conf file.
  _saveaccountconf_mutable Arvan_Token "$Arvan_Token"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if _arvan_rest POST "$_domain/dns-records" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"value\":{\"text\":\"$txtvalue\"},\"ttl\":120}"; then
    if _contains "$response" "$txtvalue"; then
      _info "response id is $response"
      _info "Added, OK"
      return 0
    elif _contains "$response" "Record Data is Duplicated"; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_arvan_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using Arvan"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  Arvan_Token="${Arvan_Token:-$(_readaccountconf_mutable Arvan_Token)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _arvan_rest GET "${_domain}/dns-records"
  if ! printf "%s" "$response" | grep \"current_page\":1 >/dev/null; then
    _err "Error on Arvan Api"
    _err "Please create a github issue with debbug log"
    return 1
  fi

  _record_id=$(echo "$response" | _egrep_o ".\"id\":\"[^\"]*\",\"type\":\"txt\",\"name\":\"_acme-challenge\",\"value\":{\"text\":\"$txtvalue\"}" | cut -d : -f 2 | cut -d , -f 1 | tr -d \")
  if ! _arvan_rest "DELETE" "${_domain}/dns-records/${_record_id}"; then
    _err "Error on Arvan Api"
    return 1
  fi
  _debug "$response"
  _contains "$response" 'dns record deleted'
  return 0
}

####################  Private functions below ##################################

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
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

    if ! _arvan_rest GET "$h"; then
      return 1
    fi
    if _contains "$response" "\"domain\":\"$h\""; then
      _domain_id=$(echo "$response" | cut -d : -f 3 | cut -d , -f 1 | tr -d \")
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_arvan_rest() {
  mtd="$1"
  ep="$2"
  data="$3"

  token_trimmed=$(echo "$Arvan_Token" | tr -d '"')
  export _H1="Authorization: $token_trimmed"

  if [ "$mtd" = "DELETE" ]; then
    #DELETE Request shouldn't have Content-Type
    _debug data "$data"
    response="$(_post "$data" "$ARVAN_API_URL/$ep" "" "$mtd")"
  elif [ "$mtd" = "POST" ]; then
    export _H2="Content-Type: application/json"
    _debug data "$data"
    response="$(_post "$data" "$ARVAN_API_URL/$ep" "" "$mtd")"
  else
    response="$(_get "$ARVAN_API_URL/$ep$data")"
  fi
  return 0
}
