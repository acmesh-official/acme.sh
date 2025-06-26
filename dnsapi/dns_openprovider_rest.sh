#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_openprovider_rest_info='OpenProvider (REST)
Domains: OpenProvider.com
Site: OpenProvider.eu
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_openprovider_rest
Options:
 OPENPROVIDER_REST_USERNAME Openprovider Account Username
 OPENPROVIDER_REST_PASSWORD Openprovider Account Password
Issues: github.com/acmesh-official/acme.sh/issues/6122
Author: Lambiek12
'

OPENPROVIDER_API_URL="https://api.openprovider.eu/v1beta"

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_openprovider_rest_add() {
  fulldomain=$1
  txtvalue=$2

  _openprovider_prepare_credentials || return 1

  _debug "Try fetch OpenProvider DNS zone details"
  if ! _get_dns_zone "$fulldomain"; then
    _err "DNS zone not found within configured OpenProvider account."
    return 1
  fi

  if [ -n "$_domain_id" ]; then
    addzonerecordrequestparameters="dns/zones/$_domain_name"
    addzonerecordrequestbody="{\"id\":$_domain_id,\"name\":\"$_domain_name\",\"records\":{\"add\":[{\"name\":\"$_sub_domain\",\"ttl\":900,\"type\":\"TXT\",\"value\":\"$txtvalue\"}]}}"

    if _openprovider_rest PUT "$addzonerecordrequestparameters" "$addzonerecordrequestbody"; then
      if _contains "$response" "\"success\":true"; then
        return 0
      elif _contains "$response" "\"Duplicate record\""; then
        _debug "Record already existed"
        return 0
      else
        _err "Adding TXT record failed due to errors."
        return 1
      fi
    fi
  fi

  _err "Adding TXT record failed due to errors."
  return 1
}

# Usage: rm  _acme-challenge.www.domain.com  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to remove the txt record after validation
dns_openprovider_rest_rm() {
  fulldomain=$1
  txtvalue=$2

  _openprovider_prepare_credentials || return 1

  _debug "Try fetch OpenProvider DNS zone details"
  if ! _get_dns_zone "$fulldomain"; then
    _err "DNS zone not found within configured OpenProvider account."
    return 1
  fi

  if [ -n "$_domain_id" ]; then
    removezonerecordrequestparameters="dns/zones/$_domain_name"
    removezonerecordrequestbody="{\"id\":$_domain_id,\"name\":\"$_domain_name\",\"records\":{\"remove\":[{\"name\":\"$_sub_domain\",\"ttl\":900,\"type\":\"TXT\",\"value\":\"\\\"$txtvalue\\\"\"}]}}"

    if _openprovider_rest PUT "$removezonerecordrequestparameters" "$removezonerecordrequestbody"; then
      if _contains "$response" "\"success\":true"; then
        return 0
      else
        _err "Removing TXT record failed due to errors."
        return 1
      fi
    fi
  fi

  _err "Removing TXT record failed due to errors."
  return 1
}

####################  OpenProvider API common functions  ####################
_openprovider_prepare_credentials() {
  OPENPROVIDER_REST_USERNAME="${OPENPROVIDER_REST_USERNAME:-$(_readaccountconf_mutable OPENPROVIDER_REST_USERNAME)}"
  OPENPROVIDER_REST_PASSWORD="${OPENPROVIDER_REST_PASSWORD:-$(_readaccountconf_mutable OPENPROVIDER_REST_PASSWORD)}"

  if [ -z "$OPENPROVIDER_REST_USERNAME" ] || [ -z "$OPENPROVIDER_REST_PASSWORD" ]; then
    OPENPROVIDER_REST_USERNAME=""
    OPENPROVIDER_REST_PASSWORD=""
    _err "You didn't specify the Openprovider username or password yet."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable OPENPROVIDER_REST_USERNAME "$OPENPROVIDER_REST_USERNAME"
  _saveaccountconf_mutable OPENPROVIDER_REST_PASSWORD "$OPENPROVIDER_REST_PASSWORD"
}

_openprovider_rest() {
  httpmethod=$1
  queryparameters=$2
  requestbody=$3

  _openprovider_rest_login
  if [ -z "$openproviderauthtoken" ]; then
    _err "Unable to fetch authentication token from Openprovider API."
    return 1
  fi

  export _H1="Content-Type: application/json"
  export _H2="Accept: application/json"
  export _H3="Authorization: Bearer $openproviderauthtoken"

  if [ "$httpmethod" != "GET" ]; then
    response="$(_post "$requestbody" "$OPENPROVIDER_API_URL/$queryparameters" "" "$httpmethod")"
  else
    response="$(_get "$OPENPROVIDER_API_URL/$queryparameters")"
  fi

  if [ "$?" != "0" ]; then
    _err "No valid parameters supplied for Openprovider API: Error $queryparameters"
    return 1
  fi

  _debug2 response "$response"

  return 0
}

_openprovider_rest_login() {
  export _H1="Content-Type: application/json"
  export _H2="Accept: application/json"

  loginrequesturl="$OPENPROVIDER_API_URL/auth/login"
  loginrequestbody="{\"ip\":\"0.0.0.0\",\"password\":\"$OPENPROVIDER_REST_PASSWORD\",\"username\":\"$OPENPROVIDER_REST_USERNAME\"}"
  loginresponse="$(_post "$loginrequestbody" "$loginrequesturl" "" "POST")"

  openproviderauthtoken="$(printf "%s\n" "$loginresponse" | _egrep_o '"token" *: *"[^"]*' | _head_n 1 | sed 's#^"token" *: *"##')"

  export openproviderauthtoken
}

####################  Private functions ##################################

# Usage: _get_dns_zone _acme-challenge.www.domain.com
# Returns:
# _domain_id=123456789
# _domain_name=domain.com
# _sub_domain=_acme-challenge.www
_get_dns_zone() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      # Empty value not allowed
      return 1
    fi

    if ! _openprovider_rest GET "dns/zones/$h" ""; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _domain_id="$(printf "%s\n" "$response" | _egrep_o '"id" *: *[^,]*' | _head_n 1 | sed 's#^"id" *: *##')"
      _debug _domain_id "$_domain_id"

      _domain_name="$h"
      _debug _domain_name "$_domain_name"

      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _debug _sub_domain "$_sub_domain"
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}
