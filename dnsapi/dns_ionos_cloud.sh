#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_ionos_cloud_info='IONOS Cloud DNS
Site: ionos.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_ionos_cloud
Options:
 IONOS_TOKEN API Token.
Issues: github.com/acmesh-official/acme.sh/issues/5243
'

# Supports IONOS Cloud DNS API v1.15.4

IONOS_CLOUD_API="https://dns.de-fra.ionos.com"
IONOS_CLOUD_ROUTE_ZONES="/zones"

dns_ionos_cloud_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _ionos_init; then
    return 1
  fi

  _record_name=$(printf "%s" "$fulldomain" | cut -d . -f 1)
  _body="{\"properties\":{\"name\":\"$_record_name\", \"type\":\"TXT\", \"content\":\"$txtvalue\"}}"

  if _ionos_cloud_rest POST "$IONOS_CLOUD_ROUTE_ZONES/$_zone_id/records" "$_body" && [ "$_code" = "202" ]; then
    _info "TXT record has been created successfully."
    return 0
  fi

  return 1
}

dns_ionos_cloud_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _ionos_init; then
    return 1
  fi

  if ! _ionos_cloud_get_record "$_zone_id" "$txtvalue" "$fulldomain"; then
    _err "Could not find _acme-challenge TXT record."
    return 1
  fi

  if _ionos_cloud_rest DELETE "$IONOS_CLOUD_ROUTE_ZONES/$_zone_id/records/$_record_id" && [ "$_code" = "202" ]; then
    _info "TXT record has been deleted successfully."
    return 0
  fi

  return 1
}

_ionos_init() {
  IONOS_TOKEN="${IONOS_TOKEN:-$(_readaccountconf_mutable IONOS_TOKEN)}"

  if [ -z "$IONOS_TOKEN" ]; then
    _err "You didn't specify an IONOS token yet."
    _err "Read https://api.ionos.com/docs/authentication/v1/#tag/tokens/operation/tokensGenerate to learn how to get a token."
    _err "You need to set it before calling acme.sh:"
    _err "\$ export IONOS_TOKEN=\"...\""
    _err "\$ acme.sh --issue -d ... --dns dns_ionos_cloud"
    return 1
  fi

  _saveaccountconf_mutable IONOS_TOKEN "$IONOS_TOKEN"

  if ! _get_cloud_zone "$fulldomain"; then
    _err "Cannot find zone $zone in your IONOS account."
    return 1
  fi

  return 0
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

_ionos_cloud_get_record() {
  zone_id=$1
  txtrecord=$2
  # this is to transform the domain to lower case
  fulldomain=$(printf "%s" "$3" | _lower_case)
  # this is to transform record name to lower case
  # IONOS Cloud API transforms all record names to lower case
  _record_name=$(printf "%s" "$fulldomain" | cut -d . -f 1 | _lower_case)

  if _ionos_cloud_rest GET "$IONOS_CLOUD_ROUTE_ZONES/$zone_id/records"; then
    _response="$(echo "$_response" | tr -d "\n")"

    pattern="\{\"id\":\"[a-fA-F0-9\-]*\",\"type\":\"record\",\"href\":\"/zones/$zone_id/records/[a-fA-F0-9\-]*\",\"metadata\":\{\"createdDate\":\"[A-Z0-9\:\.\-]*\",\"lastModifiedDate\":\"[A-Z0-9\:\.\-]*\",\"fqdn\":\"$fulldomain\",\"state\":\"AVAILABLE\",\"zoneId\":\"$zone_id\"\},\"properties\":\{\"content\":\"$txtrecord\",\"enabled\":true,\"name\":\"$_record_name\",\"priority\":[0-9]*,\"ttl\":[0-9]*,\"type\":\"TXT\"\}\}"

    _record="$(echo "$_response" | _egrep_o "$pattern")"
    if [ "$_record" ]; then
      _record_id=$(printf "%s\n" "$_record" | _egrep_o "\"id\":\"[a-fA-F0-9\-]*\"" | _head_n 1 | cut -d : -f 2 | tr -d '\"')
      return 0
    fi
  fi

  return 1
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
