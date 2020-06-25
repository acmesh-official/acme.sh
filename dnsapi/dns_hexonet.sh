#!/usr/bin/env sh

#
# Hexonet_Login="username!roleId"
#
# Hexonet_Password="rolePassword"

Hexonet_Api="https://coreapi.1api.net/api/call.cgi"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_hexonet_add() {
  fulldomain=$1
  txtvalue=$2

  Hexonet_Login="${Hexonet_Login:-$(_readaccountconf_mutable Hexonet_Login)}"
  Hexonet_Password="${Hexonet_Password:-$(_readaccountconf_mutable Hexonet_Password)}"
  if [ -z "$Hexonet_Login" ] || [ -z "$Hexonet_Password" ]; then
    Hexonet_Login=""
    Hexonet_Password=""
    _err "You must export variables: Hexonet_Login and Hexonet_Password"
    return 1
  fi

  if ! _contains "$Hexonet_Login" "!"; then
    _err "It seems that the Hexonet_Login=$Hexonet_Login is not a restrivteed user."
    _err "Please check and retry."
    return 1
  fi

  #save the username and password to the account conf file.
  _saveaccountconf_mutable Hexonet_Login "$Hexonet_Login"
  _saveaccountconf_mutable Hexonet_Password "$Hexonet_Password"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _hexonet_rest "command=QueryDNSZoneRRList&dnszone=${h}.&RRTYPE=TXT"

  if ! _contains "$response" "CODE=200"; then
    _err "Error"
    return 1
  fi

  _info "Adding record"
  if _hexonet_rest "command=UpdateDNSZone&dnszone=${_domain}.&addrr0=${_sub_domain}%20IN%20TXT%20${txtvalue}"; then
    if _contains "$response" "CODE=200"; then
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
dns_hexonet_rm() {
  fulldomain=$1
  txtvalue=$2

  Hexonet_Login="${Hexonet_Login:-$(_readaccountconf_mutable Hexonet_Login)}"
  Hexonet_Password="${Hexonet_Password:-$(_readaccountconf_mutable Hexonet_Password)}"
  if [ -z "$Hexonet_Login" ] || [ -z "$Hexonet_Password" ]; then
    Hexonet_Login=""
    Hexonet_Password=""
    _err "You must export variables: Hexonet_Login and Hexonet_Password"
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
  _hexonet_rest "command=QueryDNSZoneRRList&dnszone=${h}.&RRTYPE=TXT&RR=${_sub_domain}%20IN%20TXT%20\"${txtvalue}\""

  if ! _contains "$response" "CODE=200"; then
    _err "Error"
    return 1
  fi

  count=$(printf "%s\n" "$response" | _egrep_o "PROPERTY[TOTAL][0]=" | cut -d = -f 2)
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    if ! _hexonet_rest "command=UpdateDNSZone&dnszone=${_domain}.&delrr0=${_sub_domain}%20IN%20TXT%20\"${txtvalue}\""; then
      _err "Delete record error."
      return 1
    fi
    _contains "$response" "CODE=200"
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
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _hexonet_rest "command=QueryDNSZoneRRList&dnszone=${h}."; then
      return 1
    fi

    if _contains "$response" "CODE=200"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_hexonet_rest() {
  query_params="$1"
  _debug "$query_params"

  response="$(_get "${Hexonet_Api}?s_login=${Hexonet_Login}&s_pw=${Hexonet_Password}&${query_params}")"

  if [ "$?" != "0" ]; then
    _err "error $query_params"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
