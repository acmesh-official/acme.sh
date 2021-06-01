#!/usr/bin/env sh

#
#PORKBUN_API_KEY="pk1_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
#PORKBUN_SECRET_API_KEY="sk1_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

PORKBUN_Api="https://porkbun.com/api/json/v3"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_porkbun_add() {
  fulldomain=$1
  txtvalue=$2

  PORKBUN_API_KEY="${PORKBUN_API_KEY:-$(_readaccountconf_mutable PORKBUN_API_KEY)}"
  PORKBUN_SECRET_API_KEY="${PORKBUN_SECRET_API_KEY:-$(_readaccountconf_mutable PORKBUN_SECRET_API_KEY)}"

  if [ -z "$PORKBUN_API_KEY" ] || [ -z "$PORKBUN_SECRET_API_KEY" ]; then
    PORKBUN_API_KEY=''
    PORKBUN_SECRET_API_KEY=''
    _err "You didn't specify a Porkbun api key and secret api key yet."
    _err "You can get yours from here https://porkbun.com/account/api."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable PORKBUN_API_KEY "$PORKBUN_API_KEY"
  _saveaccountconf_mutable PORKBUN_SECRET_API_KEY "$PORKBUN_SECRET_API_KEY"

  _debug 'First detect the root zone'
  if ! _get_root "$fulldomain"; then
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # For wildcard cert, the main root domain and the wildcard domain have the same txt subdomain name, so
  # we can not use updating anymore.
  #  count=$(printf "%s\n" "$response" | _egrep_o "\"count\":[^,]*" | cut -d : -f 2)
  #  _debug count "$count"
  #  if [ "$count" = "0" ]; then
  _info "Adding record"
  if _porkbun_rest POST "dns/create/$_domain" "{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"ttl\":120}"; then
    if _contains "$response" '\"status\":"SUCCESS"'; then
      _info "Added, OK"
      return 0
    elif _contains "$response" "The record already exists"; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error. ($response)"
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1

}

#fulldomain txtvalue
dns_porkbun_rm() {
  fulldomain=$1
  txtvalue=$2

  PORKBUN_API_KEY="${PORKBUN_API_KEY:-$(_readaccountconf_mutable PORKBUN_API_KEY)}"
  PORKBUN_SECRET_API_KEY="${PORKBUN_SECRET_API_KEY:-$(_readaccountconf_mutable PORKBUN_SECRET_API_KEY)}"

  _debug 'First detect the root zone'
  if ! _get_root "$fulldomain"; then
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  count=$(echo "$response" | _egrep_o "\"count\": *[^,]*" | cut -d : -f 2 | tr -d " ")
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    record_id=$(echo "$response" | tr '{' '\n' | grep -- "$txtvalue" | cut -d, -f1 | cut -d: -f2 | tr -d \")
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if ! _porkbun_rest POST "dns/delete/$_domain/$record_id"; then
      _err "Delete record error."
      return 1
    fi
    echo "$response" | tr -d " " | grep '\"status\":"SUCCESS"' >/dev/null
  fi

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi

    if _porkbun_rest POST "dns/retrieve/$h"; then
      if _contains "$response" "\"status\":\"SUCCESS\""; then
        _domain=$h
        _sub_domain="$(echo "$fulldomain" | sed "s/\\.$_domain\$//")"
        return 0
      else
        _debug "Go to next level of $_domain"
      fi
    else
      _debug "Go to next level of $_domain"
    fi
    i=$(_math "$i" + 1)
  done

  return 1
}

_porkbun_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  api_key_trimmed=$(echo "$PORKBUN_API_KEY" | tr -d '"')
  secret_api_key_trimmed=$(echo "$PORKBUN_SECRET_API_KEY" | tr -d '"')

  test -z "$data" && data="{" || data="$(echo $data | cut -d'}' -f1),"
  data="$data\"apikey\":\"$api_key_trimmed\",\"secretapikey\":\"$secret_api_key_trimmed\"}"

  export _H1="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$PORKBUN_Api/$ep" "" "$m")"
  else
    response="$(_get "$PORKBUN_Api/$ep")"
  fi

  _sleep 3 # prevent rate limit

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
