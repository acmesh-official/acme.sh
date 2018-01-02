#!/usr/bin/env sh

# Gandi LiveDNS v5 API
# http://doc.livedns.gandi.net/
# currently under beta
#
# Requires GANDI API KEY set in GANDI_LIVEDNS_KEY set as environment variable
#
#Author: Frédéric Crozat <fcrozat@suse.com>
#Report Bugs here: https://github.com/fcrozat/acme.sh
#
########  Public functions #####################

GANDI_LIVEDNS_API="https://dns.api.gandi.net/api/v5"

#Usage: dns_gandi_livedns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_gandi_livedns_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$GANDI_LIVEDNS_KEY" ]; then
    _err "No API key specified for Gandi LiveDNS."
    _err "Create your key and export it as GANDI_LIVEDNS_KEY"
    return 1
  fi

  _saveaccountconf GANDI_LIVEDNS_KEY "$GANDI_LIVEDNS_KEY"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  _debug domain "$_domain"
  _debug sub_domain "$_sub_domain"

  _gandi_livedns_rest PUT "domains/$_domain/records/$_sub_domain/TXT" "{\"rrset_ttl\": 300, \"rrset_values\":[\"$txtvalue\"]}" \
    && _contains "$response" '{"message": "DNS Record Created"}' \
    && _info "Add $(__green "success")"
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_gandi_livedns_rm() {
  fulldomain=$1
  txtvalue=$2

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug fulldomain "$fulldomain"
  _debug domain "$_domain"
  _debug sub_domain "$_sub_domain"

  _gandi_livedns_rest DELETE "domains/$_domain/records/$_sub_domain/TXT" ""

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

    if ! _gandi_livedns_rest GET "domains/$h"; then
      return 1
    fi

    if _contains "$response" '"code": 401'; then
      _err "$response"
      return 1
    elif _contains "$response" '"code": 404'; then
      _debug "$h not found"
    else
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

_gandi_livedns_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Content-Type: application/json"
  export _H2="X-Api-Key: $GANDI_LIVEDNS_KEY"

  if [ "$m" = "GET" ]; then
    response="$(_get "$GANDI_LIVEDNS_API/$ep")"
  else
    _debug data "$data"
    response="$(_post "$data" "$GANDI_LIVEDNS_API/$ep" "" "$m")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
