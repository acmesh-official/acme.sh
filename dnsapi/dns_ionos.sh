#!/usr/bin/env sh

# Supports IONOS DNS API v1.0.1 and IONOS Cloud DNS API v1.15.4
#
# Usage:
#   Export IONOS_PREFIX and IONOS_SECRET or IONOS_TOKEN before calling acme.sh:
#
#   $ export IONOS_PREFIX="..."
#   $ export IONOS_SECRET="..."
# or 
#   $ export IONOS_TOKEN="..."
#
#   $ acme.sh --issue --dns dns_ionos ...
#
# if IONOS_PREFIX and IONOS_SECRET are set, the script will use IONOS DNS API
# if IONOS_TOKEN is set, the script will use the IONOS Cloud DNS API

IONOS_API="https://api.hosting.ionos.com/dns"
IONOS_CLOUD_API="https://dns.de-fra.ionos.com"
IONOS_ROUTE_ZONES="/v1/zones"
IONOS_CLOUD_ROUTE_ZONES="/zones"

IONOS_TXT_TTL=60 # minimum accepted by API
IONOS_TXT_PRIO=10

dns_ionos_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _ionos_init; then
    return 1
  fi

  if [ "$_context" == "core" ];then
    _body="[{\"name\":\"$_sub_domain.$_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"ttl\":$IONOS_TXT_TTL,\"prio\":$IONOS_TXT_PRIO,\"disabled\":false}]"

    if _ionos_rest POST "$IONOS_ROUTE_ZONES/$_zone_id/records" "$_body" && [ "$_code" = "201" ]; then
      _info "TXT record has been created successfully."
      return 0
    fi
  else
    _record_name=$(printf "%s" "$fulldomain" | cut -d . -f 1)
    _body="{\"properties\":{\"name\":\"$_record_name\", \"type\":\"TXT\", \"content\":\"$txtvalue\"}}"

    if _ionos_cloud_rest POST "$IONOS_CLOUD_ROUTE_ZONES/$_zone_id/records" "$_body" && [ "$_code" = "202" ]; then
      _info "TXT record has been created successfully."
      return 0
    fi
  fi

  return 1
}

dns_ionos_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _ionos_init; then
    return 1
  fi

  if [ "$_context" == "core" ];then
    if ! _ionos_get_record "$fulldomain" "$_zone_id" "$txtvalue"; then
      _err "Could not find _acme-challenge TXT record."
      return 1
    fi

    if _ionos_rest DELETE "$IONOS_ROUTE_ZONES/$_zone_id/records/$_record_id" && [ "$_code" = "200" ]; then
      _info "TXT record has been deleted successfully."
      return 0
    fi 
  else
    _record_name=$(printf "%s" "$fulldomain" | cut -d . -f 1)
    if ! _ionos_cloud_get_record "$_record_name" "$_zone_id" "$txtvalue"; then
      _err "Could not find _acme-challenge TXT record."
      return 1
    fi

    if _ionos_cloud_rest DELETE "$IONOS_CLOUD_ROUTE_ZONES/$_zone_id/records/$_record_id" && [ "$_code" = "200" ]; then
      _info "TXT record has been deleted successfully."
      return 0
    fi 

  fi

  return 1
}

_ionos_init() {
  IONOS_PREFIX="${IONOS_PREFIX:-$(_readaccountconf_mutable IONOS_PREFIX)}"
  IONOS_SECRET="${IONOS_SECRET:-$(_readaccountconf_mutable IONOS_SECRET)}"
  IONOS_TOKEN="${IONOS_TOKEN:-$(_readaccountconf_mutable IONOS_TOKEN)}"

  if [ -n "$IONOS_PREFIX" ] && [ -n "$IONOS_SECRET" ]; then
    _info "You have specified an IONOS api prefix and secret."
    _info "The script will use the IONOS DNS API: $IONOS_API"

    _saveaccountconf_mutable IONOS_PREFIX "$IONOS_PREFIX"
    _saveaccountconf_mutable IONOS_SECRET "$IONOS_SECRET"

    if ! _get_root "$fulldomain"; then
      _err "Cannot find this domain in your IONOS account."
      return 1
    fi
    _context="core" 
  elif [ -n "$IONOS_TOKEN" ]; then
    _info "You have specified an IONOS token."
    _info "The script will use the IONOS Cloud DNS API: $IONOS_CLOUD_API"

    _saveaccountconf_mutable IONOS_TOKEN "$IONOS_TOKEN"

    if ! _get_cloud_zone "$fulldomain"; then
      _err "Cannot find zone $zone in your IONOS account."
      return 1
    fi
    _context="cloud"
  else
    _err "You didn't specify any IONOS credentials yet."
    _err "If you are using the IONOS DNS API, Read https://beta.developer.hosting.ionos.de/docs/getstarted to learn how to get a prefix and secret."
    _err "If you are using the IONOS Cloud DNS API, Read https://api.ionos.com/docs/authentication/v1/#tag/tokens/operation/tokensGenerate to learn how to get a token."
    _err ""
    _err "Then set them before calling acme.sh:"
    _err "\$ export IONOS_PREFIX=\"...\""
    _err "\$ export IONOS_SECRET=\"...\""
    _err "#or"
    _err "\$ export IONOS_TOKEN=\"...\""
    _err "\$ acme.sh --issue -d ... --dns dns_ionos"
    return 1
  fi

  return 0
}

_get_root() {
  domain=$1
  i=1
  p=1

  if _ionos_rest GET "$IONOS_ROUTE_ZONES"; then
    _response="$(echo "$_response" | tr -d "\n")"

    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      if [ -z "$h" ]; then
        return 1
      fi

      _zone="$(echo "$_response" | _egrep_o "\"name\":\"$h\".*\}")"
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

_get_cloud_zone() {
  domain=$1
  zone=$(printf "%s" "$domain" | cut -d . -f 2-)

  if _ionos_cloud_rest GET "$IONOS_CLOUD_ROUTE_ZONES?filter.zoneName=$zone"; then
    _response="$(echo "$_response" | tr -d "\n")"

    _zone_list_items=$(echo "$_response" | _egrep_o "\"items\":.*")

    _zone_id=$(printf "%s\n" "$_zone_list_items" | _egrep_o "\"id\":\"[a-fA-F0-9\-]*\"" | _head_n 1 | cut -d : -f 2 | tr -d '\"')
    if [ "$_zone_id" ]; then
      return 0
    fi
  fi

  return 1
}

_ionos_get_record() {
  fulldomain=$1
  zone_id=$2
  txtrecord=$3

  if _ionos_rest GET "$IONOS_ROUTE_ZONES/$zone_id?recordName=$fulldomain&recordType=TXT"; then
    _response="$(echo "$_response" | tr -d "\n")"

    _record="$(echo "$_response" | _egrep_o "\"name\":\"$fulldomain\"[^\}]*\"type\":\"TXT\"[^\}]*\"content\":\"\\\\\"$txtrecord\\\\\"\".*\}")"
    if [ "$_record" ]; then
      _record_id=$(printf "%s\n" "$_record" | _egrep_o "\"id\":\"[a-fA-F0-9\-]*\"" | _head_n 1 | cut -d : -f 2 | tr -d '\"')

      return 0
    fi
  fi

  return 1
}

_ionos_cloud_get_record() {
  _record_name=$1
  zone_id=$2
  txtrecord=$3

  if _ionos_cloud_rest GET "$IONOS_ROUTE_ZONES/$zone_id/records"; then
    _response="$(echo "$_response" | tr -d "\n")"

    _record="$(echo "$_response" | _egrep_o "\"name\":\"$_record_name\"[^\}]*\"type\":\"TXT\"[^\}]*\"content\":\"\\\\\"$txtrecord\\\\\"\".*\}")"
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

  # clear headers
  : >"$HTTP_HEADER"

  if [ "$method" != "GET" ]; then
    export _H2="Accept: application/json"
    export _H3="Content-Type: application/json"

    _response="$(_post "$data" "$IONOS_API$route" "" "$method" "application/json")"
  else
    export _H2="Accept: */*"
    export _H3=

    _response="$(_get "$IONOS_API$route")"
  fi

  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"

  if [ "$?" != "0" ]; then
    _err "Error $route: $_response"
    return 1
  fi

  _debug2 "_response" "$_response"
  _debug2 "_code" "$_code"

  return 0
}

_ionos_cloud_rest() {
  method="$1"
  route="$2"
  data="$3"

  export _H1="Authorization: Bearer $IONOS_TOKEN"

  # clear headers
  : >"$HTTP_HEADER"

  if [ "$method" != "GET" ]; then
    _response="$(_post "$data" "$IONOS_CLOUD_API$route" "" "$method" "application/json")"
  else
    _response="$(_get "$IONOS_CLOUD_API$route")"
  fi

  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"

  if [ "$?" != "0" ]; then
    _err "Error $route: $_response"
    return 1
  fi

  _debug2 "_response" "$_response"
  _debug2 "_code" "$_code"

  return 0
}
