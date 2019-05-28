#!/usr/bin/env sh

#
# NEODIGIT_API_TOKEN="jasdfhklsjadhflnhsausdfas"

# This is Neodigit.net api wrapper for acme.sh
#
# Author: Adrian Almenar
# Report Bugs here: https://github.com/tecnocratica/acme.sh
#
NEODIGIT_API_URL="https://api.neodigit.net/v1"
#
########  Public functions #####################

# Usage: dns_myapi_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_neodigit_add() {
  fulldomain=$1
  txtvalue=$2

  NEODIGIT_API_TOKEN="${NEODIGIT_API_TOKEN:-$(_readaccountconf_mutable NEODIGIT_API_TOKEN)}"
  if [ -z "$NEODIGIT_API_TOKEN" ]; then
    NEODIGIT_API_TOKEN=""
    _err "You haven't specified a Token api key."
    _err "Please create the key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable NEODIGIT_API_TOKEN "$NEODIGIT_API_TOKEN"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _debug domain "$_domain"
  _debug sub_domain "$_sub_domain"

  _debug "Getting txt records"
  _neo_rest GET "dns/zones/${_domain_id}/records?type=TXT&name=$fulldomain"

  _debug _code "$_code"

  if [ "$_code" != "200" ]; then
    _err "error retrieving data!"
    return 1
  fi

  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _debug domain "$_domain"
  _debug sub_domain "$_sub_domain"

  _info "Adding record"
  if _neo_rest POST "dns/zones/$_domain_id/records" "{\"record\":{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"ttl\":60}}"; then
    if printf -- "%s" "$response" | grep "$_sub_domain" >/dev/null; then
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

#fulldomain txtvalue
dns_neodigit_rm() {
  fulldomain=$1
  txtvalue=$2

  NEODIGIT_API_TOKEN="${NEODIGIT_API_TOKEN:-$(_readaccountconf_mutable NEODIGIT_API_TOKEN)}"
  if [ -z "$NEODIGIT_API_TOKEN" ]; then
    NEODIGIT_API_TOKEN=""
    _err "You haven't specified a Token api key."
    _err "Please create the key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable NEODIGIT_API_TOKEN "$NEODIGIT_API_TOKEN"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _neo_rest GET "dns/zones/${_domain_id}/records?type=TXT&name=$fulldomain&content=$txtvalue"

  if [ "$_code" != "200" ]; then
    _err "error retrieving data!"
    return 1
  fi

  record_id=$(echo "$response" | _egrep_o "\"id\":\s*[0-9]+" | _head_n 1 | cut -d: -f2 | cut -d, -f1)
  _debug "record_id" "$record_id"
  if [ -z "$record_id" ]; then
    _err "Can not get record id to remove."
    return 1
  fi
  if ! _neo_rest DELETE "dns/zones/$_domain_id/records/$record_id"; then
    _err "Delete record error."
    return 1
  fi

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=dasfdsafsadg5ythd
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

    if ! _neo_rest GET "dns/zones?name=$h"; then
      return 1
    fi

    _debug p "$p"

    if _contains "$response" "\"name\":\"$h\"" >/dev/null; then
      _domain_id=$(echo "$response" | _egrep_o "\"id\":\s*[0-9]+" | _head_n 1 | cut -d: -f2 | cut -d, -f1)
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

_neo_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="X-TCPanel-Token: $NEODIGIT_API_TOKEN"
  export _H2="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$NEODIGIT_API_URL/$ep" "" "$m")"
  else
    response="$(_get "$NEODIGIT_API_URL/$ep")"
  fi

  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
