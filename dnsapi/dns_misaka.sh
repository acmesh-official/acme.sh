#!/usr/bin/env sh

# bug reports to support+acmesh@misaka.io
# based on dns_nsone.sh by dev@1e.ca

#
#Misaka_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#

Misaka_Api="https://dnsapi.misaka.io/dns"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_misaka_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$Misaka_Key" ]; then
    Misaka_Key=""
    _err "You didn't specify misaka.io dns api key yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf Misaka_Key "$Misaka_Key"

  _debug "checking root zone [$fulldomain]"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _misaka_rest GET "zones/${_domain}/recordsets?search=${_sub_domain}"

  if ! _contains "$response" "\"results\":"; then
    _err "Error"
    return 1
  fi

  count=$(printf "%s\n" "$response" | _egrep_o "\"name\":\"$_sub_domain\",[^{]*\"type\":\"TXT\"" | wc -l | tr -d " ")
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Adding record"

    if _misaka_rest POST "zones/${_domain}/recordsets/${_sub_domain}/TXT" "{\"records\":[{\"value\":\"\\\"$txtvalue\\\"\"}],\"filters\":[],\"ttl\":1}"; then
      _debug response "$response"
      if _contains "$response" "$_sub_domain"; then
        _info "Added"
        return 0
      else
        _err "Add txt record error."
        return 1
      fi
    fi
    _err "Add txt record error."
  else
    _info "Updating record"

    _misaka_rest PUT "zones/${_domain}/recordsets/${_sub_domain}/TXT?append=true" "{\"records\": [{\"value\": \"\\\"$txtvalue\\\"\"}],\"ttl\":1}"
    if [ "$?" = "0" ] && _contains "$response" "$_sub_domain"; then
      _info "Updated!"
      #todo: check if the record takes effect
      return 0
    fi
    _err "Update error"
    return 1
  fi

}

#fulldomain
dns_misaka_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _misaka_rest GET "zones/${_domain}/recordsets?search=${_sub_domain}"

  count=$(printf "%s\n" "$response" | _egrep_o "\"name\":\"$_sub_domain\",[^{]*\"type\":\"TXT\"" | wc -l | tr -d " ")
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    if ! _misaka_rest DELETE "zones/${_domain}/recordsets/${_sub_domain}/TXT"; then
      _err "Delete record error."
      return 1
    fi
    _contains "$response" ""
  fi
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=2
  p=1
  if ! _misaka_rest GET "zones?limit=1000"; then
    return 1
  fi
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_misaka_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Content-Type: application/json"
  export _H2="User-Agent: acme.sh/$VER misaka-dns-acmesh/20191213"
  export _H3="Authorization: Token $Misaka_Key"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$Misaka_Api/$ep" "" "$m")"
  else
    response="$(_get "$Misaka_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
