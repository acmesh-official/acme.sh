#!/usr/bin/env sh

# bug reports to dev@1e.ca

#
#LUA_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#LUA_Email="user@luadns.net"

LUA_Api="https://api.luadns.com/v1"
LUA_auth=$(printf "%s" "$LUA_Email:$LUA_Key" | _base64)

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_lua_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$LUA_Key" ] || [ -z "$LUA_Email" ]; then
    LUA_Key=""
    LUA_Email=""
    _err "You don't specify luadns api key and email yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf LUA_Key "$LUA_Key"
  _saveaccountconf LUA_Email "$LUA_Email"

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

  if ! _contains "$response" "\"id\":"; then
    _err "Error"
    return 1
  fi

  count=$(printf "%s\n" "$response" | _egrep_o "\"name\":\"$fulldomain\"" | wc -l)
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Adding record"
    if _LUA_rest POST "zones/$_domain_id/records" "{\"type\":\"TXT\",\"name\":\"$fulldomain.\",\"content\":\"$txtvalue\",\"ttl\":120}"; then
      if printf -- "%s" "$response" | grep "$fulldomain" >/dev/null; then
        _info "Added"
        #todo: check if the record takes effect
        return 0
      else
        _err "Add txt record error."
        return 1
      fi
    fi
    _err "Add txt record error."
  else
    _info "Updating record"
    record_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":[^,]*,\"name\":\"$fulldomain.\",\"type\":\"TXT\"" | cut -d: -f2 | cut -d, -f1)
    _debug "record_id" "$record_id"

    _LUA_rest PUT "zones/$_domain_id/records/$record_id" "{\"id\":\"$record_id\",\"type\":\"TXT\",\"name\":\"$fulldomain.\",\"content\":\"$txtvalue\",\"zone_id\":\"$_domain_id\",\"ttl\":120}"
    if [ "$?" = "0" ]; then
      _info "Updated!"
      #todo: check if the record takes effect
      return 0
    fi
    _err "Update error"
    return 1
  fi

}

#fulldomain
dns_lua_rm() {
  fulldomain=$1

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
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _domain_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":[^,]*,\"name\":\"$h\"" | cut -d : -f 2 | cut -d , -f 1)
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

  _H1="Accept: application/json"
  _H2="Authorization: Basic $LUA_auth"
  if [ "$data" ]; then
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
