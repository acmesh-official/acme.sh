#!/usr/bin/env sh

#PowerDNS Mysql backend
#
#
PDNS_Host="example.com"
PDNS_Port=3306
PDNS_User="username"
PDNS_Pass="password"
PDNS_Database="powerdns"
PDNS_Ttl=60

DEFAULT_PDNS_TTL=60

########  Public functions #####################
#Usage: add _acme-challenge.www.domain.com "123456789ABCDEF0000000000000000000000000000000000000"
#fulldomain
#txtvalue
dns_pdns-mysql_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$PDNS_Host" ]; then
    PDNS_Url=""
    _err "You didn't specify PowerDNS Mysql address."
    _err "Please set PDNS_Host and try again."
    return 1
  fi

  if [ -z "$PDNS_Port" ]; then
    PDNS_Url=""
    _err "You didn't specify PowerDNS Mysql Port."
    _err "Please set PDNS_Port and try again."
    return 1
  fi

  if [ -z "$PDNS_User" ]; then
    PDNS_User=""
    _err "You didn't specify PowerDNS Mysql username."
    _err "Please set PDNS_User and try again."
    return 1
  fi

  if [ -z "$PDNS_Pass" ]; then
    PDNS_Pass=""
    _err "You didn't specify PowerDNS Mysql password."
    _err "Please set PDNS_Pass and try again."
    return 1
  fi

  if [ -z "$PDNS_Database" ]; then
    PDNS_Database=""
    _err "You didn't specify PowerDNS Mysql database."
    _err "Please set PDNS_Database and try again."
    return 1
  fi

  if [ -z "$PDNS_Ttl" ]; then
    PDNS_Ttl="$DEFAULT_PDNS_TTL"
  fi

  #save the api addr and key to the account conf file.
  _saveaccountconf PDNS_Host "$PDNS_Host"
  _saveaccountconf PDNS_Port "$PDNS_Port"
  _saveaccountconf PDNS_User "$PDNS_User"
  _saveaccountconf PDNS_Pass "$PDNS_Pass"
  _saveaccountconf PDNS_Database "$PDNS_Database"
  
  if [ "$PDNS_Ttl" != "$DEFAULT_PDNS_TTL" ]; then
    _saveaccountconf PDNS_Ttl "$PDNS_Ttl"
  fi

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain "$_domain"

  if ! set_record "$_domain" "$fulldomain" "$txtvalue"; then
    return 1
  fi

  return 0
}

#fulldomain
dns_pdns-mysql_rm() {
  fulldomain=$1

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain "$_domain"

  if ! rm_record "$_domain" "$fulldomain"; then
    return 1
  fi

  return 0
}

set_record() {
  _info "Adding record"
  root=$1
  full=$2
  txtvalue=$3

  if ! _pdns_rest "PATCH" "/api/v1/servers/$PDNS_User/zones/$root." "{\"rrsets\": [{\"changetype\": \"REPLACE\", \"name\": \"$full.\", \"type\": \"TXT\", \"ttl\": $PDNS_Ttl, \"records\": [{\"name\": \"$full.\", \"type\": \"TXT\", \"content\": \"\\\"$txtvalue\\\"\", \"disabled\": false, \"ttl\": $PDNS_Ttl}]}]}"; then
    _err "Set txt record error."
    return 1
  fi

  if ! notify_slaves "$root"; then
    return 1
  fi

  return 0
}

rm_record() {
  _info "Remove record"
  root=$1
  full=$2

  if ! _pdns_rest "PATCH" "/api/v1/servers/$PDNS_User/zones/$root." "{\"rrsets\": [{\"changetype\": \"DELETE\", \"name\": \"$full.\", \"type\": \"TXT\"}]}"; then
    _err "Delete txt record error."
    return 1
  fi

  if ! notify_slaves "$root"; then
    return 1
  fi

  return 0
}

notify_slaves() {
  root=$1

  if ! _pdns_rest "PUT" "/api/v1/servers/$PDNS_User/zones/$root./notify"; then
    _err "Notify slaves error."
    return 1
  fi

  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _domain=domain.com
_get_root() {
  domain=$1
  i=1
  _pdns_domains=$(mysql -ss "-h${PDNS_Host}" "-P${PDNS_Port}" "-u${PDNS_User}" "-p${PDNS_Pass}" -e "SELECT name FROM ${PDNS_Database}.domains")
  if _pdns_rest "GET" "/api/v1/servers/$PDNS_User/zones"; then
    _zones_response="$response"
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      return 1
    fi

    if _contains "$_zones_response" "\"name\": \"$h.\""; then
      _domain="$h"
      return 0
    fi

    i=$(_math $i + 1)
  done
  _debug "$domain not found"

  return 1
}
