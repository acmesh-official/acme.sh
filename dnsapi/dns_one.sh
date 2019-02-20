#!/usr/bin/env sh
# -*- mode: sh; tab-width: 2; indent-tabs-mode: s; coding: utf-8 -*-

# one.com ui wrapper for acme.sh
# Author: github: @diseq
# Created: 2019-02-17
#
#     export ONECOM_USER="username"
#     export ONECOM_PASSWORD="password"
#
# Usage:
#     acme.sh --issue --dns dns_one -d example.com
#
#     only single domain supported atm

dns_one_add() {
  mysubdomain=$(printf -- "%s" "$1" | rev | cut -d"." -f3- | rev)
  mydomain=$(printf -- "%s" "$1" | rev | cut -d"." -f1-2 | rev)
  txtvalue=$2

  # get credentials
  ONECOM_USER="${ONECOM_USER:-$(_readaccountconf_mutable ONECOM_USER)}"
  ONECOM_PASSWORD="${ONECOM_PASSWORD:-$(_readaccountconf_mutable ONECOM_PASSWORD)}"
  if [ -z "$ONECOM_USER" ] || [ -z "$ONECOM_PASSWORD" ]; then
    ONECOM_USER=""
    ONECOM_PASSWORD=""
    _err "You didn't specify a one.com username and password yet."
    _err "Please create the key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable ONECOM_USER "$ONECOM_USER"
  _saveaccountconf_mutable ONECOM_PASSWORD "$ONECOM_PASSWORD"


  # Login with user and password
  postdata="loginDomain=true"
  postdata="$postdata&displayUsername=$ONECOM_USER"
  postdata="$postdata&username=$ONECOM_USER"
  postdata="$postdata&targetDomain=$mydomain"
  postdata="$postdata&password1=$ONECOM_PASSWORD"
  postdata="$postdata&loginTarget="
  #_debug postdata "$postdata"

  response="$(_post "$postdata" "https://www.one.com/admin/login.do" "" "POST" "application/x-www-form-urlencoded")"
  #_debug response "$response"

  JSESSIONID="$(grep "JSESSIONID" "$HTTP_HEADER" | grep "^[Ss]et-[Cc]ookie:" | _tail_n 1 | _egrep_o 'JSESSIONID=[^;]*;' | tr -d ';')"
  _debug jsessionid "$JSESSIONID"

  export _H1="Cookie: ${JSESSIONID}"


  # get entries
  response="$(_get "https://www.one.com/admin/api/domains/$mydomain/dns/custom_records")"
  _debug response "$response"


  CSRF_G_TOKEN="$(grep "CSRF_G_TOKEN=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o 'CSRF_G_TOKEN=[^;]*;' | tr -d ';')"
  export _H2="Cookie: ${CSRF_G_TOKEN}"


  # Update the IP address for domain entry
  postdata="{\"type\":\"dns_custom_records\",\"attributes\":{\"priority\":0,\"ttl\":600,\"type\":\"TXT\",\"prefix\":\"$mysubdomain\",\"content\":\"$txtvalue\"}}"
  _debug postdata "$postdata"
  response="$(_post "$postdata" "https://www.one.com/admin/api/domains/$mydomain/dns/custom_records" "" "POST" "application/json")"
  response="$(echo "$response" | _normalizeJson)"
  _debug response "$response"

  id=$(printf -- "%s" "$response" | sed -n "s/{\"result\":{\"data\":{\"type\":\"dns_custom_records\",\"id\":\"\([^\"]*\)\",\"attributes\":{\"prefix\":\"$mysubdomain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"priority\":0,\"ttl\":600}}},\"metadata\":null}/\1/p")

  if [ -z "$id" ]; then
    _err "Add txt record error."
    return 1
  else
    _info "Added, OK ($id)"
    return 0
  fi

}

dns_one_rm() {
  mysubdomain=$(printf -- "%s" "$1" | rev | cut -d"." -f3- | rev)
  mydomain=$(printf -- "%s" "$1" | rev | cut -d"." -f1-2 | rev)
  txtvalue=$2

  # get credentials
  ONECOM_USER="${ONECOM_USER:-$(_readaccountconf_mutable ONECOM_USER)}"
  ONECOM_PASSWORD="${ONECOM_PASSWORD:-$(_readaccountconf_mutable ONECOM_PASSWORD)}"
  if [ -z "$ONECOM_USER" ] || [ -z "$ONECOM_PASSWORD" ]; then
    ONECOM_USER=""
    ONECOM_PASSWORD=""
    _err "You didn't specify a one.com username and password yet."
    _err "Please create the key and try again."
    return 1
  fi


  # Login with user and password
  postdata="loginDomain=true"
  postdata="$postdata&displayUsername=$ONECOM_USER"
  postdata="$postdata&username=$ONECOM_USER"
  postdata="$postdata&targetDomain=$mydomain"
  postdata="$postdata&password1=$ONECOM_PASSWORD"
  postdata="$postdata&loginTarget="

  response="$(_post "$postdata" "https://www.one.com/admin/login.do" "" "POST" "application/x-www-form-urlencoded")"
  #_debug response "$response"

  JSESSIONID="$(grep "JSESSIONID" "$HTTP_HEADER" | grep "^[Ss]et-[Cc]ookie:" | _tail_n 1 | _egrep_o 'JSESSIONID=[^;]*;' | tr -d ';')"
  _debug jsessionid "$JSESSIONID"

  export _H1="Cookie: ${JSESSIONID}"


  # get entries
  response="$(_get "https://www.one.com/admin/api/domains/$mydomain/dns/custom_records")"
  response="$(echo "$response" | _normalizeJson)"
  _debug response "$response"

  CSRF_G_TOKEN="$(grep "CSRF_G_TOKEN=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o 'CSRF_G_TOKEN=[^;]*;' | tr -d ';')"
  export _H2="Cookie: ${CSRF_G_TOKEN}"

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
