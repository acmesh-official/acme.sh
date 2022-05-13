#!/usr/bin/env sh

#
#VARIOMEDIA_API_TOKEN=000011112222333344445555666677778888

VARIOMEDIA_API="https://api.variomedia.de"

######## Public functions #####################

#Usage: add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_variomedia_add() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  VARIOMEDIA_API_TOKEN="${VARIOMEDIA_API_TOKEN:-$(_readaccountconf_mutable VARIOMEDIA_API_TOKEN)}"
  if test -z "$VARIOMEDIA_API_TOKEN"; then
    VARIOMEDIA_API_TOKEN=""
    _err 'VARIOMEDIA_API_TOKEN was not exported'
    return 1
  fi

  _saveaccountconf_mutable VARIOMEDIA_API_TOKEN "$VARIOMEDIA_API_TOKEN"

  _debug 'First detect the root zone'
  if ! _get_root "$fulldomain"; then
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if ! _variomedia_rest POST "dns-records" "{\"data\": {\"type\": \"dns-record\", \"attributes\": {\"record_type\": \"TXT\", \"name\": \"$_sub_domain\", \"domain\": \"$_domain\", \"data\": \"$txtvalue\", \"ttl\":300}}}"; then
    _err "$response"
    return 1
  fi

  _debug2 _response "$response"
  return 0
}

#fulldomain txtvalue
dns_variomedia_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  VARIOMEDIA_API_TOKEN="${VARIOMEDIA_API_TOKEN:-$(_readaccountconf_mutable VARIOMEDIA_API_TOKEN)}"
  if test -z "$VARIOMEDIA_API_TOKEN"; then
    VARIOMEDIA_API_TOKEN=""
    _err 'VARIOMEDIA_API_TOKEN was not exported'
    return 1
  fi

  _saveaccountconf_mutable VARIOMEDIA_API_TOKEN "$VARIOMEDIA_API_TOKEN"

  _debug 'First detect the root zone'
  if ! _get_root "$fulldomain"; then
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug 'Getting txt records'

  if ! _variomedia_rest GET "dns-records?filter[domain]=$_domain"; then
    _err 'Error'
    return 1
  fi

  _record_id="$(echo "$response" | cut -d '[' -f2 | cut -d']' -f1 | sed 's/},[ \t]*{/\},§\{/g' | tr § '\n' | grep "$_sub_domain" | grep "$txtvalue" | sed 's/^{//;s/}[,]?$//' | tr , '\n' | tr -d '\"' | grep ^id | cut -d : -f2 | tr -d ' ')"
  _debug _record_id "$_record_id"
  if [ "$_record_id" ]; then
    _info "Successfully retrieved the record id for ACME challenge."
  else
    _info "Empty record id, it seems no such record."
    return 0
  fi

  if ! _variomedia_rest DELETE "/dns-records/$_record_id"; then
    _err "$response"
    return 1
  fi

  _debug2 _response "$response"
  return 0
}

#################### Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  fulldomain=$1
  i=1
  while true; do
    h=$(printf "%s" "$fulldomain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi

    if ! _variomedia_rest GET "domains/$h"; then
      return 1
    fi

    if _startswith "$response" "\{\"data\":"; then
      if _contains "$response" "\"id\":\"$h\""; then
        _sub_domain="$(echo "$fulldomain" | sed "s/\\.$h\$//")"
        _domain=$h
        return 0
      fi
    fi
    i=$(_math "$i" + 1)
  done

  _debug "root domain not found"
  return 1
}

_variomedia_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Authorization: token $VARIOMEDIA_API_TOKEN"
  export _H2="Content-Type: application/vnd.api+json"
  export _H3="Accept: application/vnd.variomedia.v1+json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$VARIOMEDIA_API/$ep" "" "$m")"
  else
    response="$(_get "$VARIOMEDIA_API/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "Error $ep"
    return 1
  fi

  _debug2 response "$response"
  return 0
}
