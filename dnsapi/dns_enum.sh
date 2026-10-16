#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_enum_info='enum
Site: enum.co
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_enum
Options:
 ENUM_API_KEY API key of a service account
 ENUM_PROJECT_ID Project ID
Issues: github.com/acmesh-official/acme.sh/issues/7293
Author: Roman Zipp
'

ENUM_Api="https://api.enum.co/enum.api.v1.DnsService"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_enum_add() {
  fulldomain=$(printf "%s" "$1" | _lower_case)
  txtvalue=$2

  ENUM_API_KEY="${ENUM_API_KEY:-$(_readaccountconf_mutable ENUM_API_KEY)}"
  ENUM_PROJECT_ID="${ENUM_PROJECT_ID:-$(_readaccountconf_mutable ENUM_PROJECT_ID)}"

  if [ -z "$ENUM_API_KEY" ] || [ -z "$ENUM_PROJECT_ID" ]; then
    ENUM_API_KEY=""
    ENUM_PROJECT_ID=""
    _err "You didn't specify an enum API key and project ID yet."
    _err "You can create an API key with: enumctl service-accounts create acme --key acme"
    return 1
  fi

  _saveaccountconf_mutable ENUM_API_KEY "$ENUM_API_KEY"
  _saveaccountconf_mutable ENUM_PROJECT_ID "$ENUM_PROJECT_ID"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _domain "$_domain"

  _info "Adding record"
  if _enum_rest AddRecordSetValue "{\"projectId\":\"$ENUM_PROJECT_ID\",\"zoneId\":\"$_domain_id\",\"name\":\"$fulldomain\",\"type\":\"TXT\",\"ttl\":60,\"value\":{\"content\":\"\\\"$txtvalue\\\"\"}}"; then
    _info "Added, OK"
    return 0
  fi
  _err "Add txt record error: $response"
  return 1
}

#Usage: fulldomain txtvalue
dns_enum_rm() {
  fulldomain=$(printf "%s" "$1" | _lower_case)
  txtvalue=$2

  ENUM_API_KEY="${ENUM_API_KEY:-$(_readaccountconf_mutable ENUM_API_KEY)}"
  ENUM_PROJECT_ID="${ENUM_PROJECT_ID:-$(_readaccountconf_mutable ENUM_PROJECT_ID)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _domain "$_domain"

  _info "Removing record"
  if _enum_rest RemoveRecordSetValue "{\"projectId\":\"$ENUM_PROJECT_ID\",\"zoneId\":\"$_domain_id\",\"name\":\"$fulldomain\",\"type\":\"TXT\",\"content\":\"\\\"$txtvalue\\\"\"}"; then
    _info "Removed, OK"
    return 0
  fi
  _err "Remove txt record error: $response"
  return 1
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _domain=domain.com
# _domain_id=dnszone-01kmyy3t719crcnrrvk1mgyjd0
_get_root() {
  domain=$1
  i=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi

    if _enum_rest GetZoneByName "{\"projectId\":\"$ENUM_PROJECT_ID\",\"name\":\"$h\"}"; then
      _domain_id=$(printf "%s" "$response" | _egrep_o "\"id\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")
      if [ "$_domain_id" ]; then
        _domain=$h
        return 0
      fi
    elif [ "$_code" = "401" ] || [ "$_code" = "403" ]; then
      _err "Authentication failed: $response"
      return 1
    fi

    i=$(_math "$i" + 1)
  done
}

_enum_rest() {
  method=$1
  data=$2

  export _H1="Authorization: Bearer $ENUM_API_KEY"

  _debug method "$method"
  _secure_debug2 data "$data"
  response="$(_post "$data" "$ENUM_Api/$method" "" "POST" "application/json")"
  _ret="$?"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug _code "$_code"
  _secure_debug2 response "$response"

  if [ "$_ret" != "0" ] || [ "$_code" != "200" ]; then
    return 1
  fi
  return 0
}
