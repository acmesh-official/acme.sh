#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_hostinger_info='Hostinger
Site: Hostinger.com
Domains: hostinger.nl
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_hostinger
Options:
 HOSTINGER_Token API Key
Issues: https://github.com/acmesh-official/acme.sh/issues/6831
Author: Sasha Reid <github@sasha.hackl.es>
'

HOSTINGER_Api="https://developers.hostinger.com/api/dns/v1/zones"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_hostinger_add() {
  fulldomain=$1
  txtvalue=$2

  HOSTINGER_Token="${HOSTINGER_Token:-$(_readaccountconf_mutable HOSTINGER_Token)}"

  if [ -z "$HOSTINGER_Token" ]; then
    HOSTINGER_Token=""
    _err "You didn't specify a Hostinger API Key yet."
    _err "Please read the documentation for the Hostinger API authentication at https://developers.hostinger.com/#description/authentication"
    return 1
  fi
  _saveaccountconf_mutable HOSTINGER_Token "$HOSTINGER_Token"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting existing records"
  _hostinger_rest GET "${_domain}"

  if ! echo "$response"; then
    _err "Error"
    return 1
  fi

  # For wildcard cert, the main root domain and the wildcard domain have the same txt subdomain name, so
  # we can not use updating anymore.
  #  count=$(printf "%s\n" "$response" | _egrep_o "\"count\":[^,]*" | cut -d : -f 2)
  #  _debug count "$count"
  #  if [ "$count" = "0" ]; then
  _info "Adding record"
  if _hostinger_rest PUT "$_domain" "{\"zone\":[{\"name\": \"$_sub_domain\",\"records\": [{\"content\":\"$txtvalue\"}],\"type\":\"TXT\",\"ttl\":\"120\"}],\"overwrite\":false}"; then
    if _contains "$response" "Request accepted"; then
      _info "Added, OK"
      return 0
    elif _contains "$response" "DNS resource record is not valid or conflicts with another resource record" ||
      _contains "$response" 'DNS:4008'; then
      _info "Already exists, OK"
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
dns_hostinger_rm() {
  fulldomain=$1
  txtvalue=$2

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting existing records"
  _hostinger_rest GET "${_domain}"

  if ! echo "$response"; then
    _err "Error"
    return 1
  fi

  if _contains "$response" "\"name\":\"$_sub_domain\""; then
    if ! _hostinger_rest DELETE "$_domain" "{\"filters\":[{\"name\":\"$_sub_domain\",\"type\":\"TXT\"}]}"; then
      _err "Delete record error."
      return 1
    fi
    echo "$response" | grep "Request accepted" >/dev/null
  else
    _info "Don't need to remove."
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
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _hostinger_rest GET "$h"
    if ! _contains "$response" "Domain name is not valid"; then
      if [ "$response" = "[]" ]; then
        _debug "Valid subdomains are not the root"
      else
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain=$h
        return 0
      fi
    fi

    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_hostinger_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  token_trimmed=$(echo "$HOSTINGER_Token" | tr -d '"')

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $token_trimmed"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$HOSTINGER_Api/$ep" "" "$m")"
  else
    response="$(_get "$HOSTINGER_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
