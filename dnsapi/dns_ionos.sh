#!/usr/bin/env sh

# Supports IONOS DNS API Beta v1.0.0
#
# Usage:
#   Export IONOS_PREFIX and IONOS_SECRET before calling acme.sh:
#
#   $ export IONOS_PREFIX="..."
#   $ export IONOS_SECRET="..."
#
#   $ acme.sh --issue --dns dns_ionos ...

IONOS_API="https://api.hosting.ionos.com/dns"
IONOS_ROUTE_ZONES="/v1/zones"

IONOS_TXT_TTL=60 # minimum accepted by API
IONOS_TXT_PRIO=10

dns_ionos_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _ionos_init; then
    return 1
  fi

  _body="[{\"name\":\"$_sub_domain.$_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"ttl\":$IONOS_TXT_TTL,\"prio\":$IONOS_TXT_PRIO,\"disabled\":false}]"

  if _ionos_rest POST "$IONOS_ROUTE_ZONES/$_zone_id/records" "$_body" && [ -z "$response" ]; then
    _info "TXT record has been created successfully."
    return 0
  fi

  return 1
}

dns_ionos_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _ionos_init; then
    return 1
  fi

  if ! _ionos_get_record "$fulldomain" "$_zone_id" "$txtvalue"; then
    _err "Could not find _acme-challenge TXT record."
    return 1
  fi

  if _ionos_rest DELETE "$IONOS_ROUTE_ZONES/$_zone_id/records/$_record_id" && [ -z "$response" ]; then
    _info "TXT record has been deleted successfully."
    return 0
  fi

  return 1
}

_ionos_init() {
  IONOS_PREFIX="${IONOS_PREFIX:-$(_readaccountconf_mutable IONOS_PREFIX)}"
  IONOS_SECRET="${IONOS_SECRET:-$(_readaccountconf_mutable IONOS_SECRET)}"

  if [ -z "$IONOS_PREFIX" ] || [ -z "$IONOS_SECRET" ]; then
    _err "You didn't specify an IONOS api prefix and secret yet."
    _err "Read https://beta.developer.hosting.ionos.de/docs/getstarted to learn how to get a prefix and secret."
    _err ""
    _err "Then set them before calling acme.sh:"
    _err "\$ export IONOS_PREFIX=\"...\""
    _err "\$ export IONOS_SECRET=\"...\""
    _err "\$ acme.sh --issue -d ... --dns dns_ionos"
    return 1
  fi

  _saveaccountconf_mutable IONOS_PREFIX "$IONOS_PREFIX"
  _saveaccountconf_mutable IONOS_SECRET "$IONOS_SECRET"

  if ! _get_root "$fulldomain"; then
    _err "Cannot find this domain in your IONOS account."
    return 1
  fi
}

_get_root() {
  domain=$1
  i=1
  p=1

  if _ionos_rest GET "$IONOS_ROUTE_ZONES"; then
    response="$(echo "$response" | tr -d "\n")"

    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      if [ -z "$h" ]; then
        return 1
      fi

      _zone="$(echo "$response" | _egrep_o "\"name\":\"$h\".*\}")"
      if [ "$_zone" ]; then
        _zone_id=$(printf "%s\n" "$_zone" | _egrep_o "\"id\":\"[a-fA-F0-9\-]*\"" | _head_n 1 | cut -d : -f 2 | tr -d '\"')
        if [ "$_zone_id" ]; then
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

_ionos_get_record() {
  fulldomain=$1
  zone_id=$2
  txtrecord=$3

  if _ionos_rest GET "$IONOS_ROUTE_ZONES/$zone_id?recordName=$fulldomain&recordType=TXT"; then
    response="$(echo "$response" | tr -d "\n")"

    _record="$(echo "$response" | _egrep_o "\"name\":\"$fulldomain\"[^\}]*\"type\":\"TXT\"[^\}]*\"content\":\"\\\\\"$txtrecord\\\\\"\".*\}")"
    if [ "$_record" ]; then
      _record_id=$(printf "%s\n" "$_record" | _egrep_o "\"id\":\"[a-fA-F0-9\-]*\"" | _head_n 1 | cut -d : -f 2 | tr -d '\"')

      return 0
    fi
  fi

  return 1
}

_ionos_rest() {
  method="$1"
  route="$2"
  data="$3"

  IONOS_API_KEY="$(printf "%s.%s" "$IONOS_PREFIX" "$IONOS_SECRET")"

  export _H1="X-API-Key: $IONOS_API_KEY"

  if [ "$method" != "GET" ]; then
    export _H2="Accept: application/json"
    export _H3="Content-Type: application/json"

    response="$(_post "$data" "$IONOS_API$route" "" "$method" "application/json")"
  else
    export _H2="Accept: */*"
    export _H3=
    response="$(_get "$IONOS_API$route")"
  fi

  if [ "$?" != "0" ]; then
    _err "Error $route: $response"
    return 1
  fi
  _debug2 "response" "$response"

  return 0
}
