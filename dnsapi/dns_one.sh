#!/usr/bin/env sh
# one.com ui wrapper for acme.sh

#
#     export ONECOM_User="username"
#     export ONECOM_Password="password"

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

  subdomain="${_sub_domain}"
  maindomain=${_domain}

  _debug subdomain "$subdomain"
  _debug maindomain "$maindomain"

  #Check if the TXT exists
  _dns_one_getrecord "TXT" "$subdomain" "$txtvalue"
  if [ -n "$id" ]; then
    _info "$(__green "Txt record with the same value found. Skip adding.")"
    return 0
  fi

  _dns_one_addrecord "TXT" "$subdomain" "$txtvalue"
  if [ -z "$id" ]; then
    _err "Add TXT record error."
    return 1
  else
    _info "$(__green "Added, OK ($id)")"
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

  subdomain="${_sub_domain}"
  maindomain=${_domain}

  _debug subdomain "$subdomain"
  _debug maindomain "$maindomain"

  #Check if the TXT exists
  _dns_one_getrecord "TXT" "$subdomain" "$txtvalue"
  if [ -z "$id" ]; then
    _err "Txt record not found."
    return 1
  fi

  # delete entry
  if _dns_one_delrecord "$id"; then
    _info "$(__green Removed, OK)"
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
  i=1
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

_dns_one_getrecord() {
  type="$1"
  name="$2"
  value="$3"
  if [ -z "$type" ]; then
    type="TXT"
  fi
  if [ -z "$name" ]; then
    _err "Record name is empty."
    return 1
  fi

  response="$(_get "https://www.one.com/admin/api/domains/$maindomain/dns/custom_records")"
  response="$(echo "$response" | _normalizeJson)"
  _debug response "$response"

  if [ -z "${value}" ]; then
    id=$(printf -- "%s" "$response" | sed -n "s/.*{\"type\":\"dns_custom_records\",\"id\":\"\([^\"]*\)\",\"attributes\":{\"prefix\":\"${name}\",\"type\":\"${type}\",\"content\":\"[^\"]*\",\"priority\":0,\"ttl\":600}.*/\1/p")
    response=$(printf -- "%s" "$response" | sed -n "s/.*{\"type\":\"dns_custom_records\",\"id\":\"[^\"]*\",\"attributes\":{\"prefix\":\"${name}\",\"type\":\"${type}\",\"content\":\"\([^\"]*\)\",\"priority\":0,\"ttl\":600}.*/\1/p")
  else
    id=$(printf -- "%s" "$response" | sed -n "s/.*{\"type\":\"dns_custom_records\",\"id\":\"\([^\"]*\)\",\"attributes\":{\"prefix\":\"${name}\",\"type\":\"${type}\",\"content\":\"${value}\",\"priority\":0,\"ttl\":600}.*/\1/p")
  fi
  if [ -z "$id" ]; then
    return 1
  fi
  return 0
}

_dns_one_addrecord() {
  type="$1"
  name="$2"
  value="$3"
  if [ -z "$type" ]; then
    type="TXT"
  fi
  if [ -z "$name" ]; then
    _err "Record name is empty."
    return 1
  fi

  postdata="{\"type\":\"dns_custom_records\",\"attributes\":{\"priority\":0,\"ttl\":600,\"type\":\"${type}\",\"prefix\":\"${name}\",\"content\":\"${value}\"}}"
  _debug postdata "$postdata"
  response="$(_post "$postdata" "https://www.one.com/admin/api/domains/$maindomain/dns/custom_records" "" "POST" "application/json")"
  response="$(echo "$response" | _normalizeJson)"
  _debug response "$response"

  id=$(echo "$response" | sed -n "s/{\"result\":{\"data\":{\"type\":\"dns_custom_records\",\"id\":\"\([^\"]*\)\",\"attributes\":{\"prefix\":\"$subdomain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"priority\":0,\"ttl\":600}}},\"metadata\":null}/\1/p")

  if [ -z "$id" ]; then
    return 1
  else
    return 0
  fi
}

_dns_one_delrecord() {
  id="$1"
  if [ -z "$id" ]; then
    return 1
  fi

  response="$(_post "" "https://www.one.com/admin/api/domains/$maindomain/dns/custom_records/$id" "" "DELETE" "application/json")"
  response="$(echo "$response" | _normalizeJson)"
  _debug response "$response"

  if [ "$response" = '{"result":null,"metadata":null}' ]; then
    return 0
  else
    return 1
  fi
}
