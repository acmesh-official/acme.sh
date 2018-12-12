#!/usr/bin/env sh

#
#PointHQ_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#PointHQ_Email="xxxx@sss.com"

PointHQ_Api="https://api.pointhq.com"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_pointhq_add() {
  fulldomain=$1
  txtvalue=$2

  PointHQ_Key="${PointHQ_Key:-$(_readaccountconf_mutable PointHQ_Key)}"
  PointHQ_Email="${PointHQ_Email:-$(_readaccountconf_mutable PointHQ_Email)}"
  if [ -z "$PointHQ_Key" ] || [ -z "$PointHQ_Email" ]; then
    PointHQ_Key=""
    PointHQ_Email=""
    _err "You didn't specify a PointHQ API key and email yet."
    _err "Please create the key and try again."
    return 1
  fi

  if ! _contains "$PointHQ_Email" "@"; then
    _err "It seems that the PointHQ_Email=$PointHQ_Email is not a valid email address."
    _err "Please check and retry."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable PointHQ_Key "$PointHQ_Key"
  _saveaccountconf_mutable PointHQ_Email "$PointHQ_Email"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if _pointhq_rest POST "zones/$_domain/records" "{\"zone_record\": {\"name\":\"$_sub_domain\",\"record_type\":\"TXT\",\"data\":\"$txtvalue\",\"ttl\":3600}}"; then
    if printf -- "%s" "$response" | grep "$fulldomain" >/dev/null; then
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
dns_pointhq_rm() {
  fulldomain=$1
  txtvalue=$2

  PointHQ_Key="${PointHQ_Key:-$(_readaccountconf_mutable PointHQ_Key)}"
  PointHQ_Email="${PointHQ_Email:-$(_readaccountconf_mutable PointHQ_Email)}"
  if [ -z "$PointHQ_Key" ] || [ -z "$PointHQ_Email" ]; then
    PointHQ_Key=""
    PointHQ_Email=""
    _err "You didn't specify a PointHQ API key and email yet."
    _err "Please create the key and try again."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _pointhq_rest GET "zones/${_domain}/records?record_type=TXT&name=$_sub_domain"

  if ! printf "%s" "$response" | grep "^\[" >/dev/null; then
    _err "Error"
    return 1
  fi

  if [ "$response" = "[]" ]; then
    _info "No records to remove."
  else
    record_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":[^,]*" | cut -d : -f 2 | tr -d \" | head -n 1)
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if ! _pointhq_rest DELETE "zones/$_domain/records/$record_id"; then
      _err "Delete record error."
      return 1
    fi
    _contains "$response" '"status":"OK"'
  fi
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
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _pointhq_rest GET "zones"; then
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

_pointhq_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  _pointhq_auth=$(printf "%s:%s" "$PointHQ_Email" "$PointHQ_Key" | _base64)

  export _H1="Authorization: Basic $_pointhq_auth"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$PointHQ_Api/$ep" "" "$m")"
  else
    response="$(_get "$PointHQ_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
