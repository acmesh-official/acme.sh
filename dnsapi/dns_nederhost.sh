#!/usr/bin/env sh

#NederHost_Key="sdfgikogfdfghjklkjhgfcdcfghjk"

NederHost_Api="https://api.nederhost.nl/dns/v1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nederhost_add() {
  fulldomain=$1
  txtvalue=$2

  NederHost_Key="${NederHost_Key:-$(_readaccountconf_mutable NederHost_Key)}"
  if [ -z "$NederHost_Key" ]; then
    NederHost_Key=""
    _err "You didn't specify a NederHost api key."
    _err "You can get yours from https://www.nederhost.nl/mijn_nederhost"
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable NederHost_Key "$NederHost_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if _nederhost_rest PATCH "zones/$_domain/records/$fulldomain/TXT" "[{\"content\":\"$txtvalue\",\"ttl\":60}]"; then
    if _contains "$response" "$fulldomain"; then
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
dns_nederhost_rm() {
  fulldomain=$1
  txtvalue=$2

  NederHost_Key="${NederHost_Key:-$(_readaccountconf_mutable NederHost_Key)}"
  if [ -z "$NederHost_Key" ]; then
    NederHost_Key=""
    _err "You didn't specify a NederHost api key."
    _err "You can get yours from https://www.nederhost.nl/mijn_nederhost"
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
  _nederhost_rest DELETE "zones/${_domain}/records/$fulldomain/TXT?content=$txtvalue"

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

    if _nederhost_rest GET "zones/${_domain}"; then
      if [ "${_code}" = "204" ]; then
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

_nederhost_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Authorization: Bearer $NederHost_Key"
  export _H2="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$NederHost_Api/$ep" "" "$m")"
  else
    response="$(_get "$NederHost_Api/$ep")"
  fi

  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_code"

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
