#!/usr/bin/env sh
# dns.la Domain api
#
#LA_Id="test123"
#
#LA_Key="d1j2fdo4dee3948"
DNSLA_API="https://www.dns.la/api/"
########  Public functions #####################
#Usage: dns_la_add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_la_add() {
  fulldomain=$1
  txtvalue=$2

  LA_Id="${LA_Id:-$(_readaccountconf_mutable LA_Id)}"
  LA_Key="${LA_Key:-$(_readaccountconf_mutable LA_Key)}"
  if [ -z "$LA_Id" ] || [ -z "$LA_Key" ]; then
    LA_Id=""
    LA_Key=""
    _err "You don't specify dnsla api id and key yet."
    _err "Please create your key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable LA_Id "$LA_Id"
  _saveaccountconf_mutable LA_Key "$LA_Key"

  _debug "detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  add_record "$_domain" "$_sub_domain" "$txtvalue"

}

#fulldomain txtvalue
dns_la_rm() {
  fulldomain=$1
  txtvalue=$2
  _fullkey=$(printf "%s" "$fulldomain" | awk '{ string=substr($0, 17); print string; }' | tr '.' '_')

  LA_Id="${LA_Id:-$(_readaccountconf_mutable LA_Id)}"
  LA_Key="${LA_Key:-$(_readaccountconf_mutable LA_Key)}"
  _debug fullkey "$_fullkey"
  RM_recordid="$(_readaccountconf "$_fullkey")"
  _debug rm_recordid "$RM_recordid"
  _debug "detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  if ! _rest GET "record.ashx?cmd=get&apiid=$LA_Id&apipass=$LA_Key&rtype=json&domainid=$_domain_id&domain=$_domain&recordid=$RM_recordid"; then
    _err "get record lis error."
    return 1
  fi

  if ! _contains "$response" "$RM_recordid"; then
    _info "no need to remove record."
    return 0
  fi

  if ! _rest GET "record.ashx?cmd=remove&apiid=$LA_Id&apipass=$LA_Key&rtype=json&domainid=$_domain_id&domain=$_domain&recordid=$RM_recordid"; then
    _err "record remove error."
    return 1
  fi

  _clearaccountconf "$_fullkey"

  _contains "$response" "\"code\":300"
}

#add the txt record.
#usage: root  sub  txtvalue
add_record() {
  root=$1
  sub=$2
  txtvalue=$3
  fulldomain="$sub.$root"

  _info "adding txt record"

  if ! _rest GET "record.ashx?cmd=create&apiid=$LA_Id&apipass=$LA_Key&rtype=json&domainid=$_domain_id&host=$_sub_domain&recordtype=TXT&recorddata=$txtvalue&recordline="; then
    return 1
  fi

  if _contains "$response" "\"code\":300"; then
    _record_id=$(printf "%s" "$response" | grep '"resultid"' | cut -d : -f 2 | cut -d , -f 1 | tr -d '\r' | tr -d '\n')
    _fullkey=$(printf "%s" "$fulldomain" | awk '{ string=substr($0, 17); print string; }' | tr '.' '_')
    _debug fullkey "$_fullkey"
    _saveaccountconf "$_fullkey" "$_record_id"
    _debug _record_id "$_record_id"
  fi
  _contains "$response" "\"code\":300"
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

    if ! _rest GET "domain.ashx?cmd=get&apiid=$LA_Id&apipass=$LA_Key&rtype=json&domain=$h"; then
      return 1
    fi

    if _contains "$response" "\"code\":300"; then
      _domain_id=$(printf "%s" "$response" | grep '"domainid"' | cut -d : -f 2 | cut -d , -f 1 | tr -d '\r' | tr -d '\n')
      _debug _domain_id "$_domain_id"
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _debug _sub_domain "$_sub_domain"
        _domain="$h"
        _debug _domain "$_domain"
        return 0
      fi
      return 1
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

#Usage: method  URI  data
_rest() {
  m="$1"
  ep="$2"
  data="$3"
  _debug "$ep"
  url="$DNSLA_API$ep"

  _debug url "$url"

  if [ "$m" = "GET" ]; then
    response="$(_get "$url" | tr -d ' ' | tr "}" ",")"
  else
    _debug2 data "$data"
    response="$(_post "$data" "$url" | tr -d ' ' | tr "}" ",")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
