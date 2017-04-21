#!/usr/bin/env sh

#This is the vscale.io api wrapper for acme.sh
#
#Author: Alex Loban
#Report Bugs here: https://github.com/LAV45/acme.sh

#VSCALE_API_KEY="sdfsdfsdfljlbjkljlkjsdfoiwje"
VSCALE_API_URL="https://api.vscale.io/v1"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_vscale_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$VSCALE_API_KEY" ]; then
    VSCALE_API_KEY=""
    _err "You didn't specify the VSCALE api key yet."
    _err "Please create you key and try again."
    return 1
  fi

  _saveaccountconf VSCALE_API_KEY "$VSCALE_API_KEY"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _vscale_tmpl_json="{\"type\":\"TXT\",\"name\":\"$_sub_domain.$_domain\",\"content\":\"$txtvalue\"}"

  if _vscale_rest POST "domains/$_domain_id/records/" "$_vscale_tmpl_json"; then
    response=$(printf "%s\n" "$response" | _egrep_o "{\"error\": \".+\"" | cut -d : -f 2)
    if [ -z "$response" ]; then
      _info "txt record updated success."
      return 0
    fi
  fi

  return 1
}

#fulldomain txtvalue
dns_vscale_rm() {
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
  _vscale_rest GET "domains/$_domain_id/records/"

  if [ -n "$response" ]; then
    record_id=$(printf "%s\n" "$response" | _egrep_o "\"TXT\", \"id\": [0-9]+, \"name\": \"$_sub_domain.$_domain\"" | cut -d : -f 2 | tr -d ", \"name\"")
    _debug record_id "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if _vscale_rest DELETE "domains/$_domain_id/records/$record_id" && [ -z "$response" ]; then
      _info "txt record deleted success."
      return 0
    fi
    _debug response "$response"
    return 1
  fi

  return 1
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=12345
_get_root() {
  domain=$1
  i=2
  p=1

  if _vscale_rest GET "domains/"; then
    response="$(echo "$response" | tr -d "\n" | sed 's/{/\n&/g')"
    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      _debug h "$h"
      if [ -z "$h" ]; then
        #not valid
        return 1
      fi

      hostedzone="$(echo "$response" | _egrep_o "{.*\"name\":\s*\"$h\".*}")"
      if [ "$hostedzone" ]; then
        _domain_id=$(printf "%s\n" "$hostedzone" | _egrep_o "\"id\":\s*[0-9]+" | _head_n 1 | cut -d : -f 2 | tr -d \ )
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
  fi
  return 1
}

#method uri qstr data
_vscale_rest() {
  mtd="$1"
  ep="$2"
  data="$3"

  _debug mtd "$mtd"
  _debug ep "$ep"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  export _H3="X-Token: ${VSCALE_API_KEY}"

  if [ "$mtd" != "GET" ]; then
    # both POST and DELETE.
    _debug data "$data"
    response="$(_post "$data" "$VSCALE_API_URL/$ep" "" "$mtd")"
  else
    response="$(_get "$VSCALE_API_URL/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
