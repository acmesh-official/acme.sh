#!/usr/bin/env sh

#
#AD_API_KEY="sdfsdfsdfljlbjkljlkjsdfoiwje"

#This is the Alwaysdata api wrapper for acme.sh
#
#Author: Paul Koppen
#Report Bugs here: https://github.com/wpk-/acme.sh

AD_API_URL="https://$AD_API_KEY:@api.alwaysdata.com/v1"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ad_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$AD_API_KEY" ]; then
    AD_API_KEY=""
    _err "You didn't specify the AD api key yet."
    _err "Please create you key and try again."
    return 1
  fi

  _saveaccountconf AD_API_KEY "$AD_API_KEY"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _ad_tmpl_json="{\"domain\":$_domain_id,\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"value\":\"$txtvalue\"}"

  if _ad_rest POST "record/" "$_ad_tmpl_json" && [ -z "$response" ]; then
    _info "txt record updated success."
    return 0
  fi

  return 1
}

#fulldomain txtvalue
dns_ad_rm() {
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
  _ad_rest GET "record/?domain=$_domain_id&name=$_sub_domain"

  if [ -n "$response" ]; then
    record_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":\s*[0-9]+" | cut -d : -f 2 | tr -d " " | _head_n 1)
    _debug record_id "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if _ad_rest DELETE "record/$record_id/" && [ -z "$response" ]; then
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

  if _ad_rest GET "domain/"; then
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
_ad_rest() {
  mtd="$1"
  ep="$2"
  data="$3"

  _debug mtd "$mtd"
  _debug ep "$ep"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"

  if [ "$mtd" != "GET" ]; then
    # both POST and DELETE.
    _debug data "$data"
    response="$(_post "$data" "$AD_API_URL/$ep" "" "$mtd")"
  else
    response="$(_get "$AD_API_URL/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
