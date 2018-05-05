#!/usr/bin/env sh
# -*- mode: sh; tab-width: 2; indent-tabs-mode: s; coding: utf-8 -*-

# one.com ui wrapper for acme.sh
# Author: github: @diseq
# Created: 2018-04-15
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
  txtvalue=$2

  # get credentials
  ONECOM_USER="${ONECOM_USER:-$(_readaccountconf_mutable ONECOM_USER)}"
  ONECOM_PASSWORD="${ONECOM_PASSWORD:-$(_readaccountconf_mutable ONECOM_PASSWORD)}"
  if [ -z "$ONECOM_USER" ] || [ -z "$ONECOM_PASSWORD" ]; then
    ONECOM_USER=""
    ONECOM_PASSWORD=""
    _err "You didn't specify a cloudflare api key and email yet."
    _err "Please create the key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable ONECOM_USER "$ONECOM_USER"
  _saveaccountconf_mutable ONECOM_PASSWORD "$ONECOM_PASSWORD"


  # Login with user and password
  postdata="loginDomain=true"
  postdata=postdata+"&displayUsername=$ONECOM_USER&username=$ONECOM_USER"
  postdata=postdata+"&targetDomain="
  postdata=postdata+"&password1=$ONECOM_PASSWORD"
  postdata=postdata+"&loginTarget="

  response="$(_post "$postdata" "https://www.one.com/admin/login.do" "" "POST")"

  JSESSIONID="$(grep "JSESSIONID=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o 'JSESSIONID=[^;]*;' | tr -d ';')"

  export _H1="Cookie: ${JSESSIONID}"

  response="$(_get "https://www.one.com/admin/dns-overview.do")"
  CSRF_G_TOKEN="$(grep "CSRF_G_TOKEN=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o 'CSRF_G_TOKEN=[^;]*;' | tr -d ';')"

  export _H2="Cookie: ${CSRF_G_TOKEN}"

  mycsrft=$(echo "${CSRF_G_TOKEN}" | sed -n 's/CSRF_G_TOKEN=\(.*\)/\1/p')

  # create txt record
  postdata="cmd=create"
  postdata=postdata+"&subDomain=$mysubdomain"
  postdata=postdata+"&priority="
  postdata=postdata+"&ttl=600"
  postdata=postdata+"&type=TXT"
  postdata=postdata+"&value=$txtvalue"
  postdata=postdata+"&csrft=$mycsrft"

  response="$(_post "$postdata" "https://www.one.com/admin/dns-web-handler.do" "" "POST")"
  _debug response "$response"

  if printf -- "%s" "$response" | grep "\"success\":true" >/dev/null; then
    _info "Added, OK"
    return 0
  else
    _err "Add txt record error."
    return 1
  fi

}

dns_one_rm() {
  mysubdomain=$(printf -- "%s" "$1" | rev | cut -d"." -f3- | rev)
  txtvalue=$2

  # get credentials
  ONECOM_USER="${ONECOM_USER:-$(_readaccountconf_mutable ONECOM_USER)}"
  ONECOM_PASSWORD="${ONECOM_PASSWORD:-$(_readaccountconf_mutable ONECOM_PASSWORD)}"
  if [ -z "$ONECOM_USER" ] || [ -z "$ONECOM_PASSWORD" ]; then
    ONECOM_USER=""
    ONECOM_PASSWORD=""
    _err "You didn't specify a cloudflare api key and email yet."
    _err "Please create the key and try again."
    return 1
  fi


  # Login with user and password
  postdata="loginDomain=true"
  postdata=postdata+"&displayUsername=$ONECOM_USER&username=$ONECOM_USER"
  postdata=postdata+"&targetDomain="
  postdata=postdata+"&password1=$ONECOM_PASSWORD"
  postdata=postdata+"&loginTarget="

  response="$(_post "$postdata" "https://www.one.com/admin/login.do" "" "POST")"

  JSESSIONID="$(grep "JSESSIONID=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o 'JSESSIONID=[^;]*;' | tr -d ';')"

  export _H1="Cookie: ${JSESSIONID}"

  response="$(_get "https://www.one.com/admin/dns-overview.do")"
  CSRF_G_TOKEN="$(grep "CSRF_G_TOKEN=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o 'CSRF_G_TOKEN=[^;]*;' | tr -d ';')"

  export _H2="Cookie: ${CSRF_G_TOKEN}"

  mycsrft=$(echo "${CSRF_G_TOKEN}" | sed -n 's/CSRF_G_TOKEN=\(.*\)/\1/p')

  # Update the IP address for domain entry
  postdata="csrft=$mycsrft"
  response="$(_post "$postdata" "https://www.one.com/admin/ajax-dns-entries.do" "" "POST")"
  response="$(echo "$response" | _normalizeJson)"

  _debug response "$response"

  # remove _acme-challenge subdomain
  mysubdomainid=$(printf -- "%s" "$response" | sed -n "s/.*{\"subDomain\":\"$mysubdomain\"[^}]*,\"value\":\"$txtvalue\",\"id\":\"\([0-9][0-9]*\)\"}.*/\1/p")

  if [ "$mysubdomainid" ]; then

    _debug mysubdomainid "$mysubdomainid"

    response="$(_get "https://www.one.com/admin/dns-overview.do")"
    CSRF_G_TOKEN="$(grep "CSRF_G_TOKEN=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o 'CSRF_G_TOKEN=[^;]*;' | tr -d ';')"

    export _H2="Cookie: ${CSRF_G_TOKEN}"

    mycsrft=$(echo "${CSRF_G_TOKEN}" | sed -n 's/CSRF_G_TOKEN=\(.*\)/\1/p')

    # delete txt record
    postdata="cmd=delete"
    postdata=postdata+"&subDomain=$mysubdomain"
    postdata=postdata+"&priority="
    postdata=postdata+"&ttl=600"
    postdata=postdata+"&type=TXT"
    postdata=postdata+"&id=$mysubdomainid"
    postdata=postdata+"&csrft=$mycsrft"

    response="$(_post "$postdata" "https://www.one.com/admin/dns-web-handler.do" "" "POST")"
    _debug "$response"

    if printf -- "%s" "$response" | grep "\"success\":true" >/dev/null; then
      _info "Removed, OK"
      return 0
    else
      _err "Removing txt record error."
      return 1
    fi

  fi

  _err "Removing txt record error. (not existing)"
  return 1

}
