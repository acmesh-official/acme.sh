#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_dnsexit_info='DNSExit.com
Site: DNSExit.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_dnsexit
Options:
 DNSEXIT_API_KEY API Key
Issues: github.com/acmesh-official/acme.sh/issues/4719
Author: Samuel Jimenez
'

DNSEXIT_API_URL="https://api.dnsexit.com/dns/"

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

  _dnsexit_zone_op add ',"ttl":0,"overwrite":false'
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

  _dnsexit_zone_op delete ''
}

####################  Private functions below ##################################
# The legacy zone-detection endpoint (update.dnsexit.com/ipupdate/hosts.jsp)
# was shut down by DNSExit and now returns 503, and the JSON API offers no
# zone-list call. So find the root zone by attempting the actual operation at
# each domain level: the API answers "code":0 only when the domain matches a
# zone of the account. https://github.com/acmesh-official/acme.sh/issues/6914
#Usage: _dnsexit_zone_op <add|delete> <extra-json-fields>
_dnsexit_zone_op() {
  _op="$1"
  _extra="$2"
  i=1
  while true; do
    _domain=$(printf "%s" "$fulldomain" | cut -d . -f "$i"-100)
    _debug _domain "$_domain"
    if [ -z "$_domain" ]; then
      _err "Could not find the root zone of $fulldomain in your DNSExit account"
      return 1
    fi

    _sub_domain="$(printf "%s" "$fulldomain" | sed "s/\\.$_domain\$//")"
    if [ "$_sub_domain" = "$fulldomain" ]; then
      _sub_domain=""
    fi
    _debug _sub_domain "$_sub_domain"

    if _dnsexit_rest "{\"domain\":\"$_domain\",\"$_op\":{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\"$_extra}}"; then
      if _contains "$response" "\"code\":0" || _contains "$response" "\"code\": 0"; then
        _debug2 _response "$response"
        return 0
      fi
      _debug "Zone $_domain was not accepted, trying the next level" "$response"
    fi
    i=$(_math "$i" + 1)
  done
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

get_account_info() {
  DNSEXIT_API_KEY="${DNSEXIT_API_KEY:-$(_readaccountconf_mutable DNSEXIT_API_KEY)}"
  if test -z "$DNSEXIT_API_KEY"; then
    DNSEXIT_API_KEY=''
    _err 'DNSEXIT_API_KEY was not exported'
    return 1
  fi

  _saveaccountconf_mutable DNSEXIT_API_KEY "$DNSEXIT_API_KEY"

  return 0
}
