#!/usr/bin/bash

#Hosttech_Key="asdfasdfawefasdfawefasdafe"

Hosttech_Api="https://api.ns1.hosttech.eu/api/user/v1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_hosttech_add() {
  fulldomain=$1
  txtvalue=$2

  Hosttech_Key="${Hosttech_Key:-$(_readaccountconf_mutable Hosttech_Key)}"
  if [ -z "$Hosttech_Key" ]; then
    Hosttech_Key=""
    _err "You didn't specify a Hosttech api key"
    _err "You can get yours from https://www.myhosttech.eu/user/dns/api"
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable Hosttech_Key "$Hosttech_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if _hosttech_rest POST "zones/$_domain/records" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"text\":\"$txtvalue\",\"ttl\":600}"; then
    if _contains "$_response" "$_sub_domain"; then
      _debug recordID "$(echo "$_response" | grep -o '"id":[^"]*' | grep -Po "\d+")"

      #save the created recordID to the account conf file, so we can read it back for deleting in dns_hosttech_rm.
      _saveaccountconf recordID "$(echo "$_response" | grep -o '"id":[^"]*' | grep -Po "\d+")"
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
dns_hosttech_rm() {
  fulldomain=$1
  txtvalue=$2

  Hosttech_Key="${Hosttech_Key:-$(_readaccountconf_mutable Hosttech_Key)}"
  if [ -z "$Hosttech_Key" ]; then
    Hosttech_Key=""
    _err "You didn't specify a Hosttech api key."
    _err "You can get yours from https://www.hosttech.nl/mijn_hosttech"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Removing txt record"
  delRecordID="$(_readaccountconf "recordID")"
  _hosttech_rest DELETE "zones/$_domain/records/$delRecordID"

  _clearaccountconf recordID
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    _domain=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
    _debug _domain "$_domain"
    if [ -z "$_domain" ]; then
      #not valid
      return 1
    fi

    if _hosttech_rest GET "zones?query=${_domain}"; then
      if [ "$(echo "$_response" | grep -o '"name":"[^"]*' | cut -d'"' -f4)" = "${_domain}" ]; then
        return 0
      fi
    else
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_hosttech_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Authorization: Bearer $Hosttech_Key"
  export _H2="accept: application/json"
  export _H3="Content-Type: application/json"

  _debug data "$data"
  _response="$(_post "$data" "$Hosttech_Api/$ep" "" "$m")"

  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_code"

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi

  _debug2 response "$_response"
  return 0
}
