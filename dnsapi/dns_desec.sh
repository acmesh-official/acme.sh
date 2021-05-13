#!/usr/bin/env sh
#
# deSEC.io Domain API
#
# Author: Zheng Qian
#
# deSEC API doc
# https://desec.readthedocs.io/en/latest/

REST_API="https://desec.io/api/v1/domains"

########  Public functions #####################

#Usage: dns_desec_add   _acme-challenge.foobar.dedyn.io   "d41d8cd98f00b204e9800998ecf8427e"
dns_desec_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using desec.io api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  DEDYN_TOKEN="${DEDYN_TOKEN:-$(_readaccountconf_mutable DEDYN_TOKEN)}"
  DEDYN_NAME="${DEDYN_NAME:-$(_readaccountconf_mutable DEDYN_NAME)}"

  if [ -z "$DEDYN_TOKEN" ] || [ -z "$DEDYN_NAME" ]; then
    DEDYN_TOKEN=""
    DEDYN_NAME=""
    _err "You did not specify DEDYN_TOKEN and DEDYN_NAME yet."
    _err "Please create your key and try again."
    _err "e.g."
    _err "export DEDYN_TOKEN=d41d8cd98f00b204e9800998ecf8427e"
    _err "export DEDYN_NAME=foobar.dedyn.io"
    return 1
  fi
  #save the api token and name to the account conf file.
  _saveaccountconf_mutable DEDYN_TOKEN "$DEDYN_TOKEN"
  _saveaccountconf_mutable DEDYN_NAME "$DEDYN_NAME"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain" "$REST_API/"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # Get existing TXT record
  _debug "Getting txt records"
  txtvalues="\"\\\"$txtvalue\\\"\""
  _desec_rest GET "$REST_API/$DEDYN_NAME/rrsets/$_sub_domain/TXT/"

  if [ "$_code" = "200" ]; then
    oldtxtvalues="$(echo "$response" | _egrep_o "\"records\":\\[\"\\S*\"\\]" | cut -d : -f 2 | tr -d "[]\\\\\"" | sed "s/,/ /g")"
    _debug "existing TXT found"
    _debug oldtxtvalues "$oldtxtvalues"
    if [ -n "$oldtxtvalues" ]; then
      for oldtxtvalue in $oldtxtvalues; do
        txtvalues="$txtvalues, \"\\\"$oldtxtvalue\\\"\""
      done
    fi
  fi
  _debug txtvalues "$txtvalues"
  _info "Adding record"
  body="[{\"subname\":\"$_sub_domain\", \"type\":\"TXT\", \"records\":[$txtvalues], \"ttl\":3600}]"

  if _desec_rest PUT "$REST_API/$DEDYN_NAME/rrsets/" "$body"; then
    if _contains "$response" "$txtvalue"; then
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

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_desec_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using desec.io api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  DEDYN_TOKEN="${DEDYN_TOKEN:-$(_readaccountconf_mutable DEDYN_TOKEN)}"
  DEDYN_NAME="${DEDYN_NAME:-$(_readaccountconf_mutable DEDYN_NAME)}"

  if [ -z "$DEDYN_TOKEN" ] || [ -z "$DEDYN_NAME" ]; then
    DEDYN_TOKEN=""
    DEDYN_NAME=""
    _err "You did not specify DEDYN_TOKEN and DEDYN_NAME yet."
    _err "Please create your key and try again."
    _err "e.g."
    _err "export DEDYN_TOKEN=d41d8cd98f00b204e9800998ecf8427e"
    _err "export DEDYN_NAME=foobar.dedyn.io"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain" "$REST_API/"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # Get existing TXT record
  _debug "Getting txt records"
  txtvalues=""
  _desec_rest GET "$REST_API/$DEDYN_NAME/rrsets/$_sub_domain/TXT/"

  if [ "$_code" = "200" ]; then
    oldtxtvalues="$(echo "$response" | _egrep_o "\"records\":\\[\"\\S*\"\\]" | cut -d : -f 2 | tr -d "[]\\\\\"" | sed "s/,/ /g")"
    _debug "existing TXT found"
    _debug oldtxtvalues "$oldtxtvalues"
    if [ -n "$oldtxtvalues" ]; then
      for oldtxtvalue in $oldtxtvalues; do
        if [ "$txtvalue" != "$oldtxtvalue" ]; then
          txtvalues="$txtvalues, \"\\\"$oldtxtvalue\\\"\""
        fi
      done
    fi
  fi
  txtvalues="$(echo "$txtvalues" | cut -c3-)"
  _debug txtvalues "$txtvalues"

  _info "Deleting record"
  body="[{\"subname\":\"$_sub_domain\", \"type\":\"TXT\", \"records\":[$txtvalues], \"ttl\":3600}]"
  _desec_rest PUT "$REST_API/$DEDYN_NAME/rrsets/" "$body"
  if [ "$_code" = "200" ]; then
    _info "Deleted, OK"
    return 0
  fi

  _err "Delete txt record error."
  return 1
}

####################  Private functions below ##################################

_desec_rest() {
  m="$1"
  ep="$2"
  data="$3"

  export _H1="Authorization: Token $DEDYN_TOKEN"
  export _H2="Accept: application/json"
  export _H3="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _secure_debug2 data "$data"
    response="$(_post "$data" "$ep" "" "$m")"
  else
    response="$(_get "$ep")"
  fi
  _ret="$?"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_code"
  _secure_debug2 response "$response"
  if [ "$_ret" != "0" ]; then
    _err "error $ep"
    return 1
  fi

  response="$(printf "%s" "$response" | _normalizeJson)"
  return 0
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain="$1"
  ep="$2"
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _desec_rest GET "$ep"; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\"" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}
