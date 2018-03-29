#!/usr/bin/env sh

# bug reports to dev@1e.ca

# ME_Key=qmlkdjflmkqdjf	
# ME_Secret=qmsdlkqmlksdvnnpae

ME_Api=https://api.dnsmadeeasy.com/V2.0/dns/managed

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_me_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$ME_Key" ] || [ -z "$ME_Secret" ]; then
    ME_Key=""
    ME_Secret=""
    _err "You didn't specify DNSMadeEasy api key and secret yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf ME_Key "$ME_Key"
  _saveaccountconf ME_Secret "$ME_Secret"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _me_rest GET "${_domain_id}/records?recordName=$_sub_domain&type=TXT"

  if ! _contains "$response" "\"totalRecords\":"; then
    _err "Error"
    return 1
  fi

  _info "Adding record"
  if _me_rest POST "$_domain_id/records/" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"value\":\"$txtvalue\",\"gtdLocation\":\"DEFAULT\",\"ttl\":120}"; then
    if printf -- "%s" "$response" | grep \"id\": >/dev/null; then
      _info "Added"
      #todo: check if the record takes effect
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi

}

#fulldomain
dns_me_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _me_rest GET "${_domain_id}/records?recordName=$_sub_domain&type=TXT"

  count=$(printf "%s\n" "$response" | _egrep_o "\"totalRecords\":[^,]*" | cut -d : -f 2)
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    record_id=$(printf "%s\n" "$response" | _egrep_o ",\"value\":\"..$txtvalue..\",\"id\":[^,]*" | cut -d : -f 3 | head -n 1)
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if ! _me_rest DELETE "$_domain_id/records/$record_id"; then
      _err "Delete record error."
      return 1
    fi
    _contains "$response" ''
  fi
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
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _me_rest GET "name?domainname=$h"; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _domain_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":[^,]*" | head -n 1 | cut -d : -f 2 | tr -d '}')
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain="$h"
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_me_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  cdate=$(LANG=C date -u +"%a, %d %b %Y %T %Z")
  hmac=$(printf "%s" "$cdate" | _hmac sha1 "$(printf "%s" "$ME_Secret" | _hex_dump | tr -d " ")" hex)

  export _H1="x-dnsme-apiKey: $ME_Key"
  export _H2="x-dnsme-requestDate: $cdate"
  export _H3="x-dnsme-hmac: $hmac"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$ME_Api/$ep" "" "$m")"
  else
    response="$(_get "$ME_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
