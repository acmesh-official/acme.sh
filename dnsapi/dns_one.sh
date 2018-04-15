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
  # todo use $1 but split host and domain
  #mysubdomain=$1
  mysubdomain="_acme-challenge"
  txtvalue=$2

  # Login with user and password
  postdata="loginDomain=true"
  postdata+="&displayUsername=$ONECOM_USER&username=$ONECOM_USER"
  postdata+="&targetDomain="
  postdata+="&password1=$ONECOM_PASSWORD"
  postdata+="&loginTarget="

  response="$(_post "$postdata" "https://www.one.com/admin/login.do" "" "POST")"

  JSESSIONID="$(grep "JSESSIONID=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o 'JSESSIONID=[^;]*;' | tr -d ';')"

  export _H1="Cookie: ${JSESSIONID}"

  response="$(_get "https://www.one.com/admin/dns-overview.do")"
  CSRF_G_TOKEN="$(grep "CSRF_G_TOKEN=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o 'CSRF_G_TOKEN=[^;]*;' | tr -d ';')"

  export _H2="Cookie: ${CSRF_G_TOKEN}"

  mycsrft=$(echo "${CSRF_G_TOKEN}" | sed -n 's/CSRF_G_TOKEN=\(.*\)/\1/p')

  # create txt record
  postdata="cmd=create"
  postdata+="&subDomain=$mysubdomain"
  postdata+="&priority="
  postdata+="&ttl=600"
  postdata+="&type=TXT"
  postdata+="&value=$txtvalue"
  postdata+="&csrft=$mycsrft"

  response="$(_post "$postdata" "https://www.one.com/admin/dns-web-handler.do" "" "POST")"
  echo $response

}

dns_one_rm() {
  # todo use $1 but split host and domain
  #mysubdomain=$1
  mysubdomain="_acme-challenge"
  txtvalue=$2

  # Login with user and password
  postdata="loginDomain=true"
  postdata+="&displayUsername=$ONECOM_USER&username=$ONECOM_USER"
  postdata+="&targetDomain="
  postdata+="&password1=$ONECOM_PASSWORD"
  postdata+="&loginTarget="

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

  # remove all records named _acme-challenge
  echo  $response | egrep -o '\{"subDomain":"_acme-challenge"[^}]*,"id":"[0-9][0-9]*"\}' | while read line ; do
    mysubdomainid=$(echo $line | sed -n 's/.*{"subDomain":"_acme-challenge"[^}]*"id":"\([0-9][0-9]*\)"}.*/\1/p')

    response="$(_get "https://www.one.com/admin/dns-overview.do")"
    CSRF_G_TOKEN="$(grep "CSRF_G_TOKEN=" "$HTTP_HEADER" | grep "^Set-Cookie:" | _tail_n 1 | _egrep_o 'CSRF_G_TOKEN=[^;]*;' | tr -d ';')"

    export _H2="Cookie: ${CSRF_G_TOKEN}"

    mycsrft=$(echo "${CSRF_G_TOKEN}" | sed -n 's/CSRF_G_TOKEN=\(.*\)/\1/p')

    # delete txt record
    postdata="cmd=delete"
    postdata+="&subDomain=$mysubdomain"
    postdata+="&priority="
    postdata+="&ttl=600"
    postdata+="&type=TXT"
    postdata+="&id=$mysubdomainid"
    postdata+="&csrft=$mycsrft"

    response="$(_post "$postdata" "https://www.one.com/admin/dns-web-handler.do" "" "POST")"
    echo $response

  done

}
