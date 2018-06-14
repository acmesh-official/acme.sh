#!/usr/bin/env sh

#
#Leaseweb_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#Author m-boone

Leaseweb_Api="https://api.leaseweb.com/hosting/v2/domains"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_leaseweb_add() {
  fulldomain=$1
  txtvalue=$2

  Leaseweb_Key="${Leaseweb_Key:-$(_readaccountconf_mutable Leaseweb_Key)}"
  if [ -z "$Leaseweb_Key" ]; then
    Leaseweb_Key=""
    _err "You didn't specify a leaseweb api key yet."
    _err "Please create the key and try again."
    return 1
  fi

  #save the api key to the account conf file.
  _saveaccountconf_mutable Leaseweb_Key "$Leaseweb_Key"

  _debug "First detect the root zone"
  if ! _dns_leaseweb_get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  if ! _dns_leaseweb_api_call GET "/$_domain/resourceRecordSets/$fulldomain/TXT"; then
    _err "Error"
    return 1
  fi

  #if empty or error response then we create it, otherwise we will need to grab the content from the response and update it with the new line
  if _contains "$response" "\"name\":\"$fulldomain.\"" >/dev/null; then
    _info "TXT Records set found. Updating records set with new item"
    recordSet=$(printf "%s\n" "$response" | _egrep_o "\"content\":\[.*\]" | cut -d [ -f 2 | cut -d ] -f 1 | sed -e "s/\\\u0022//g")
    _debug recordSet "$recordSet"
    if ! _contains "$recordSet" "\"$txtvalue\"" >/dev/null; then
      if _dns_leaseweb_api_call PUT "/$_domain/resourceRecordSets/$fulldomain/TXT" "{\"content\":[\"$txtvalue\",$recordSet], \"ttl\":60}"; then
        response_decoded="$(echo "$response" | _dbase64)"
        _debug response_decoded "$response_decoded"
        if _contains "$response_decoded" "\"name\":\"$fulldomain.\"" >/dev/null; then
          _info "Added, OK"
          return 0
        fi
      fi
    else
      _info "Record already present, OK"
      return 0
    fi
  else
    _info "No TXT records set found. Adding records set"
    if _dns_leaseweb_api_call POST "/$_domain/resourceRecordSets" "{\"type\":\"TXT\",\"name\":\"$fulldomain\",\"content\": [ \"$txtvalue\" ],\"ttl\":60}"; then
      response_decoded="$(echo "$response" | _dbase64)"
      _debug response_decoded "$response_decoded"
      if _contains "$response_decoded" "\"name\":\"$fulldomain.\"" >/dev/null; then
        _info "Added, OK"
        return 0
      fi
    fi
  fi
  _err "Add txt record error."
  return 1
}

#fulldomain txtvalue
dns_leaseweb_rm() {
  fulldomain=$1
  txtvalue=$2

  Leaseweb_Key="${Leaseweb_Key:-$(_readaccountconf_mutable Leaseweb_Key)}"
  if [ -z "$Leaseweb_Key" ]; then
    Leaseweb_Key=""
    _err "You didn't specify a leaseweb api key yet."
    _err "Please create the key and try again."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _dns_leaseweb_get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _dns_leaseweb_api_call GET "/$_domain/resourceRecordSets/$fulldomain/TXT"

  if ! _contains "$response" "\"name\":\"$fulldomain.\"" >/dev/null; then
    _err "Error no TXT record found"
    return 1
  fi

  recordSet=$(printf "%s\n" "$response" | _egrep_o "\"content\":\[.*\]" | cut -d [ -f 2 | cut -d ] -f 1 | sed -e "s/\\\u0022//g")
  _debug recordSet "$recordSet"

  if _contains "$recordSet" "\"$txtvalue\"" >/dev/null; then
    #todo: break record set into array then join again
    recordSet=$(printf "%s\n" "$recordSet" | sed -e "s/,\"$txtvalue\"//")
    recordSet=$(printf "%s\n" "$recordSet" | sed -e "s/\"$txtvalue\",//")
    recordSet=$(printf "%s\n" "$recordSet" | sed -e "s/\"$txtvalue\"//")
    if [ -z "$recordSet" ]; then
      _info "TXT Record is the only item in records set. Deleting records set"
      if ! _dns_leaseweb_api_call DELETE "/$_domain/resourceRecordSets/$fulldomain/TXT"; then
        _err "Delete record error."
        return 1
      fi
    else
      _info "TXT Record is not the only item in records set. Updating records set to remove this item."
      if _dns_leaseweb_api_call PUT "/$_domain/resourceRecordSets/$fulldomain/TXT" "{\"content\": [ $recordSet ], \"ttl\":60}"; then
        response_decoded="$(echo "$response" | _dbase64)"
        _debug response_decoded "$response_decoded"
        if ! _contains "$response_decoded" "\"name\":\"$fulldomain.\"" >/dev/null; then
          _err "Delete record error."
          return 1
        fi
      else
        _err "Delete record error."
        return 1
      fi
    fi
  else
    _info "Record not found. Don't need to remove."
  fi
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_dns_leaseweb_get_root() {
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

    if ! _dns_leaseweb_api_call GET "/$h"; then
      return 1
    fi

    if _contains "$response" "\"domainName\":\"$h\"" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_dns_leaseweb_api_call() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="X-Lsw-Auth: $Leaseweb_Key"
  export _H2="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$Leaseweb_Api$ep" "1" "$m")"
  else
    response="$(_get "$Leaseweb_Api$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug response "$response"
  return 0
}
