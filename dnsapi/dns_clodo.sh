#!/usr/bin/env sh

#This is the clodo.ru api wrapper for acme.sh
#
#Author: Oleg Zaikin <zord@mail.ru>
#Report Bugs here: https://github.com/zord1k/acme.sh

#
#CLODO_User="jdoe@example.com"
#CLODO_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#

CLODO_AUTH_URL="https://api.clodo.ru"
CLODO_API=""
CLODO_TOKEN=""

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_clodo_add() {
  _clodo_init

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

  _info "Adding record"
  if _clodo_rest POST "dns/$_domain_id" "{\"name_0\":\"$_sub_domain\",\"type_0\":\"TXT\",\"content_0\":\"$txtvalue\",\"ttl_0\":120}"; then
    if printf -- "%s" "$response" | grep "\"name\":\"$fulldomain\",\"type\":\"TXT\",\"content\":\"$txtvalue\"" >/dev/null; then
      _info "Added, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_clodo_rm() {
  _clodo_init

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
  if ! _clodo_rest GET "dns/$_domain_id"; then
    _err "Error"
    return 1
  fi

  if ! _contains "$response" "$txtvalue"; then
    _info "Don't need to remove."
  else
    record_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":\"[^\"]*\",\"domain_id\":\"$_domain_id\",\"name\":\"$fulldomain\",\"type\":\"TXT\",\"content\":\"$txtvalue\"" | cut -d : -f 2 | cut -d , -f 1 | tr -d \" | head -n 1)
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if ! _clodo_rest DELETE "dns/$_domain_id" "{\"delete_record\":$record_id}"; then
      _err "Delete record error."
      return 1
    fi
    _contains "$response" 'new_soa'
  fi

}

####################  Private functions below ##################################
_clodo_init() {
  CLODO_User="${CLODO_User:-$(_readaccountconf_mutable CLODO_User)}"
  CLODO_Key="${CLODO_Key:-$(_readaccountconf_mutable CLODO_Key)}"

  if [ -z "$CLODO_User" ] || [ -z "$CLODO_Key" ]; then
    CLODO_User=""
    CLODO_Key=""
    _err "You didn't specify a Clodo user and api key yet."
    _err "Please create the key and try again."
    return 1
  fi

  #save the api user and key to the account conf file.
  _saveaccountconf_mutable CLODO_User "$CLODO_User"
  _saveaccountconf_mutable CLODO_Key "$CLODO_Key"

  export _H1="X-Auth-User: $CLODO_User"
  export _H2="X-Auth-Key: $CLODO_Key"

  _get $CLODO_AUTH_URL "onlyheader"

  CLODO_TOKEN=$(grep "^X-Auth-Token" $HTTP_HEADER | tr -d "\r" | cut -d " " -f 2)
  CLODO_API=$(grep "^X-Server-Management-Url" $HTTP_HEADER | tr -d "\r" | cut -d " " -f 2)

  if [ -z "$CLODO_TOKEN" ] || [ -z "$CLODO_API" ]; then
    _err "Authentication error"
    return 1
  else
    _debug token "$CLODO_TOKEN"
  fi
}

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

    if ! _clodo_rest GET "dns"; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _domain_id=$(printf "%s" "$response" | _egrep_o "\"id\":\"[^\"]*\",\"name\":\"$h\"" | cut -d : -f 2 | cut -d , -f 1 | tr -d \")
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

_clodo_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="X-Auth-Token: $CLODO_TOKEN"
  export _H2="Accept: application/json"
  export _H3="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$CLODO_API/$ep" "" "$m")"
  else
    response="$(_get "$CLODO_API/$ep")"
  fi
  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
