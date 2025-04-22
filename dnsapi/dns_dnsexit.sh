#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_dnsexit_info='DNSExit.com
Site: DNSExit.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_dnsexit
Options:
 DNSEXIT_API_KEY API Key
 DNSEXIT_AUTH_USER Username
 DNSEXIT_AUTH_PASS Password
Issues: github.com/acmesh-official/acme.sh/issues/4719
Author: Samuel Jimenez
'

DNSEXIT_API_URL="https://api.dnsexit.com/dns/"
DNSEXIT_HOSTS_URL="https://update.dnsexit.com/ipupdate/hosts.jsp"

########  Public functions #####################
#Usage: dns_dnsexit_add   _acme-challenge.*.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnsexit_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using DNSExit.com"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _debug 'Load account auth'
  if ! get_account_info; then
    return 1
  fi

  _debug 'First detect the root zone'
  if ! _get_root "$fulldomain"; then
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if ! _dnsexit_rest "{\"domain\":\"$_domain\",\"add\":{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"ttl\":0,\"overwrite\":false}}"; then
    _err "$response"
    return 1
  fi

  _debug2 _response "$response"
  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_dnsexit_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using DNSExit.com"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _debug 'Load account auth'
  if ! get_account_info; then
    return 1
  fi

  _debug 'First detect the root zone'
  if ! _get_root "$fulldomain"; then
    _err "$response"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if ! _dnsexit_rest "{\"domain\":\"$_domain\",\"delete\":{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\"}}"; then
    _err "$response"
    return 1
  fi

  _debug2 _response "$response"
  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=1
  while true; do
    _domain=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$_domain"
    if [ -z "$_domain" ]; then
      return 1
    fi

    _debug login "$DNSEXIT_AUTH_USER"
    _debug password "$DNSEXIT_AUTH_PASS"
    _debug domain "$_domain"

    _dnsexit_http "login=$DNSEXIT_AUTH_USER&password=$DNSEXIT_AUTH_PASS&domain=$_domain"

    if _contains "$response" "0=$_domain"; then
      _sub_domain="$(echo "$fulldomain" | sed "s/\\.$_domain\$//")"
      return 0
    else
      _debug "Go to next level of $_domain"
    fi
    i=$(_math "$i" + 1)
  done

  return 1
}

_dnsexit_rest() {
  m=POST
  ep=""
  data="$1"
  _debug _dnsexit_rest "$ep"
  _debug data "$data"

  api_key_trimmed=$(echo "$DNSEXIT_API_KEY" | tr -d '"')

  export _H1="apikey: $api_key_trimmed"
  export _H2='Content-Type: application/json'

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$DNSEXIT_API_URL/$ep" "" "$m")"
  else
    response="$(_get "$DNSEXIT_API_URL/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "Error $ep"
    return 1
  fi

  _debug2 response "$response"
  return 0
}

_dnsexit_http() {
  m=GET
  param="$1"
  _debug param "$param"
  _debug get "$DNSEXIT_HOSTS_URL?$param"

  response="$(_get "$DNSEXIT_HOSTS_URL?$param")"

  _debug response "$response"

  if [ "$?" != "0" ]; then
    _err "Error $param"
    return 1
  fi

  _debug2 response "$response"
  return 0
}

get_account_info() {

  DNSEXIT_API_KEY="${DNSEXIT_API_KEY:-$(_readaccountconf_mutable DNSEXIT_API_KEY)}"
  if test -z "$DNSEXIT_API_KEY"; then
    DNSEXIT_API_KEY=''
    _err 'DNSEXIT_API_KEY was not exported'
    return 1
  fi

  _saveaccountconf_mutable DNSEXIT_API_KEY "$DNSEXIT_API_KEY"

  DNSEXIT_AUTH_USER="${DNSEXIT_AUTH_USER:-$(_readaccountconf_mutable DNSEXIT_AUTH_USER)}"
  if test -z "$DNSEXIT_AUTH_USER"; then
    DNSEXIT_AUTH_USER=""
    _err 'DNSEXIT_AUTH_USER was not exported'
    return 1
  fi

  _saveaccountconf_mutable DNSEXIT_AUTH_USER "$DNSEXIT_AUTH_USER"

  DNSEXIT_AUTH_PASS="${DNSEXIT_AUTH_PASS:-$(_readaccountconf_mutable DNSEXIT_AUTH_PASS)}"
  if test -z "$DNSEXIT_AUTH_PASS"; then
    DNSEXIT_AUTH_PASS=""
    _err 'DNSEXIT_AUTH_PASS was not exported'
    return 1
  fi

  _saveaccountconf_mutable DNSEXIT_AUTH_PASS "$DNSEXIT_AUTH_PASS"

  return 0
}
