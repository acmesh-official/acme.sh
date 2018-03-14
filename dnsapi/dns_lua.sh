#!/usr/bin/env sh

# bug reports to dev@1e.ca

#
#LUA_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#LUA_Email="user@luadns.net"

LUA_Api="https://api.luadns.com/v1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_lua_add() {
  fulldomain=$1
  txtvalue=$2

  LUA_Key="${LUA_Key:-$(_readaccountconf_mutable LUA_Key)}"
  LUA_Email="${LUA_Email:-$(_readaccountconf_mutable LUA_Email)}"
  LUA_auth=$(printf "%s" "$LUA_Email:$LUA_Key" | _base64)

  if [ -z "$LUA_Key" ] || [ -z "$LUA_Email" ]; then
    LUA_Key=""
    LUA_Email=""
    _err "You don't specify luadns api key and email yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable LUA_Key "$LUA_Key"
  _saveaccountconf_mutable LUA_Email "$LUA_Email"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if _LUA_rest POST "zones/$_domain_id/records" "{\"type\":\"TXT\",\"name\":\"$fulldomain.\",\"content\":\"$txtvalue\",\"ttl\":120}"; then
    if _contains "$response" "$fulldomain"; then
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
dns_lua_rm() {
  fulldomain=$1
  txtvalue=$2

  LUA_Key="${LUA_Key:-$(_readaccountconf_mutable LUA_Key)}"
  LUA_Email="${LUA_Email:-$(_readaccountconf_mutable LUA_Email)}"
  LUA_auth=$(printf "%s" "$LUA_Email:$LUA_Key" | _base64)
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _LUA_rest GET "zones/${_domain_id}/records"

  count=$(printf "%s\n" "$response" | _egrep_o "\"name\":\"$fulldomain.\",\"type\":\"TXT\"" | wc -l | tr -d " ")
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    record_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":[^,]*,\"name\":\"$fulldomain.\",\"type\":\"TXT\"" | _head_n 1 | cut -d: -f2 | cut -d, -f1)
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if ! _LUA_rest DELETE "/zones/$_domain_id/records/$record_id"; then
      _err "Delete record error."
      return 1
    fi
    _contains "$response" "$record_id"
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
  if ! _LUA_rest GET "zones"; then
    return 1
  fi
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _domain_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":[^,]*,\"name\":\"$h\"" | cut -d : -f 2 | cut -d , -f 1)
      _debug _domain_id "$_domain_id"
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

_LUA_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Accept: application/json"
  export _H2="Authorization: Basic $LUA_auth"
  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$LUA_Api/$ep" "" "$m")"
  else
    response="$(_get "$LUA_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
