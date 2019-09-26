#!/usr/bin/env sh
# -*- mode: sh; tab-width: 2; indent-tabs-mode: s; coding: utf-8 -*-

# one.com ui wrapper for acme.sh
# Author: github: @diseq
# Created: 2019-02-17
# Fixed by: @der-berni
# Modified: 2019-05-31
#
#     export ONECOM_User="username"
#     export ONECOM_Password="password"
#
# Usage:
#     acme.sh --issue --dns dns_one -d example.com
#
#     only single domain supported atm

dns_one_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _dns_one_login; then
    _err "login failed"
    return 1
  fi

  _debug "detect the root domain"
  if ! _get_root "$fulldomain"; then
    _err "root domain not found"
    return 1
  fi

  mysubdomain=$_sub_domain
  mydomain=$_domain
  _debug mysubdomain "$mysubdomain"
  _debug mydomain "$mydomain"

  # get entries
  response="$(_get "https://www.one.com/admin/api/domains/$mydomain/dns/custom_records")"
  _debug response "$response"

  # Update the IP address for domain entry
  postdata="{\"type\":\"dns_custom_records\",\"attributes\":{\"priority\":0,\"ttl\":600,\"type\":\"TXT\",\"prefix\":\"$mysubdomain\",\"content\":\"$txtvalue\"}}"
  _debug postdata "$postdata"
  response="$(_post "$postdata" "https://www.one.com/admin/api/domains/$mydomain/dns/custom_records" "" "POST" "application/json")"
  response="$(echo "$response" | _normalizeJson)"
  _debug response "$response"

  id=$(echo "$response" | sed -n "s/{\"result\":{\"data\":{\"type\":\"dns_custom_records\",\"id\":\"\([^\"]*\)\",\"attributes\":{\"prefix\":\"$mysubdomain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"priority\":0,\"ttl\":600}}},\"metadata\":null}/\1/p")

  if [ -z "$id" ]; then
    _err "Add txt record error."
    return 1
  else
    _info "Added, OK ($id)"
    return 0
  fi

}

dns_one_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _dns_one_login; then
    _err "login failed"
    return 1
  fi

  _debug "detect the root domain"
  if ! _get_root "$fulldomain"; then
    _err "root domain not found"
    return 1
  fi

  mysubdomain=$_sub_domain
  mydomain=$_domain
  _debug mysubdomain "$mysubdomain"
  _debug mydomain "$mydomain"

  # get entries
  response="$(_get "https://www.one.com/admin/api/domains/$mydomain/dns/custom_records")"
  response="$(echo "$response" | _normalizeJson)"
  _debug response "$response"

  id=$(printf -- "%s" "$response" | sed -n "s/.*{\"type\":\"dns_custom_records\",\"id\":\"\([^\"]*\)\",\"attributes\":{\"prefix\":\"$mysubdomain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"priority\":0,\"ttl\":600}.*/\1/p")

  if [ -z "$id" ]; then
    _err "Txt record not found."
    return 1
  fi

  # delete entry
  response="$(_post "$postdata" "https://www.one.com/admin/api/domains/$mydomain/dns/custom_records/$id" "" "DELETE" "application/json")"
  response="$(echo "$response" | _normalizeJson)"
  _debug response "$response"

  if [ "$response" = '{"result":null,"metadata":null}' ]; then
    _info "Removed, OK"
    return 0
  else
    _err "Removing txt record error."
    return 1
  fi

}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain="$1"
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)

    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    response="$(_get "https://www.one.com/admin/api/domains/$h/dns/custom_records")"

    if ! _contains "$response" "CRMRST_000302"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  _err "Unable to parse this domain"
  return 1
}

_dns_one_login() {

  # get credentials
  ONECOM_User="${ONECOM_User:-$(_readaccountconf_mutable ONECOM_User)}"
  ONECOM_Password="${ONECOM_Password:-$(_readaccountconf_mutable ONECOM_Password)}"
  if [ -z "$ONECOM_User" ] || [ -z "$ONECOM_Password" ]; then
    ONECOM_User=""
    ONECOM_Password=""
    _err "You didn't specify a one.com username and password yet."
    _err "Please create the key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable ONECOM_User "$ONECOM_User"
  _saveaccountconf_mutable ONECOM_Password "$ONECOM_Password"

  # Login with user and password
  postdata="loginDomain=true"
  postdata="$postdata&displayUsername=$ONECOM_User"
  postdata="$postdata&username=$ONECOM_User"
  postdata="$postdata&targetDomain="
  postdata="$postdata&password1=$ONECOM_Password"
  postdata="$postdata&loginTarget="
  #_debug postdata "$postdata"

  response="$(_post "$postdata" "https://www.one.com/admin/login.do" "" "POST" "application/x-www-form-urlencoded")"
  #_debug response "$response"

  # Get SessionID
  JSESSIONID="$(grep "OneSIDCrmAdmin" "$HTTP_HEADER" | grep "^[Ss]et-[Cc]ookie:" | _head_n 1 | _egrep_o 'OneSIDCrmAdmin=[^;]*;' | tr -d ';')"
  _debug jsessionid "$JSESSIONID"

  if [ -z "$JSESSIONID" ]; then
    _err "error sessionid cookie not found"
    return 1
  fi

  export _H1="Cookie: ${JSESSIONID}"

  return 0
}
