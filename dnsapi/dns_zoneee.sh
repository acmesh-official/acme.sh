#!/usr/bin/env sh

ZONEEE_api="https://api.zone.eu/v2/dns"

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_zoneee_add() {
  fulldomain=$1
  txtvalue=$2

  ZONEEE_User="${ZONEEE_User:-$(_readaccountconf_mutable ZONEEE_User)}"
  ZONEEE_Key="${ZONEEE_Key:-$(_readaccountconf_mutable ZONEEE_Key)}"
  if [ -z "$ZONEEE_User" ] || [ -z "$ZONEEE_Key" ]; then
    ZONEEE_User=""
    ZONEEE_Key=""
    _err "You haven't specified zone.ee user and api key."
    _err "Please Add your credentials and try again."
    _err "Username as ZONEEE_User."
    _err "API key as ZONEEE_Key."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable ZONEEE_User "$ZONEEE_User"
  _saveaccountconf_mutable ZONEEE_Key "$ZONEEE_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _zoneee_rest GET "$_domain/txt"

  if printf "%s" "$response" | grep \"result\":error >/dev/null; then
    _err "Error"
    return 1
  fi

  _info "Adding record"
  if _zoneee_rest POST "$_domain/txt" "{\"name\":\"$fulldomain\",\"destination\":\"$txtvalue\"}"; then
    if printf -- "%s" "$response" | grep "$fulldomain" >/dev/null; then
      _info "Added, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_zoneee_rm() {
  fulldomain=$1
  txtvalue=$2

  ZONEEE_User="${ZONEEE_User:-$(_readaccountconf_mutable ZONEEE_User)}"
  ZONEEE_Key="${ZONEEE_Key:-$(_readaccountconf_mutable ZONEEE_Key)}"
  if [ -z "$ZONEEE_User" ] || [ -z "$ZONEEE_Key" ]; then
    ZONEEE_User=""
    ZONEEE_Key=""
    _err "You haven't specified zone.ee user and api key."
    _err "Please Add your credentials and try again."
    _err "Username as ZONEEE_User."
    _err "API key as ZONEEE_Key."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable ZONEEE_User "$ZONEEE_User"
  _saveaccountconf_mutable ZONEEE_Key "$ZONEEE_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _zoneee_rest GET "$_domain/txt"

  if printf "%s" "$response" | grep \"result\":error >/dev/null; then
    _err "Error"
    return 1
  fi

  if ! printf "%s" "$response" | grep "\"name\":\"$fulldomain\"" >/dev/null; then
    _info "Don't need to remove."
  else
    record_id=$(printf "%s\\n" "$response" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | head -n 1)
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if ! _zoneee_rest DELETE "$_domain/txt/$record_id"; then
      _err "Delete record error."
      return 1
    fi
    return 0
  fi
}

####################  Private functions below ##################################
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

    if ! _zoneee_rest GET "$h"; then
      return 1
    fi

    if _contains "$response" "\"identificator\":\"$h\"" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_zoneee_rest() {
  m=$1
  ep="$2"
  data="$3"

  _debug "m: '$1'"
  _debug "ep: '$2'"
  _debug "data: '$3'"

  base64_auth=$(printf %s $ZONEEE_User:$ZONEEE_Key | _base64)
  export _H1="authorization: Basic $base64_auth"
  export _H2="Content-Type: application/json"
  #_debug "user: '$ZONEEE_User'"
  #_debug "api key: '$ZONEEE_Key'"
  #_debug "auth header: '$_H1'"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$ZONEEE_api/$ep" "" "$m")"
  else
    response="$(_get "$ZONEEE_api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
