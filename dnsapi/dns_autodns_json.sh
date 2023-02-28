#!/usr/bin/env sh
# -*- mode: sh; tab-width: 2; indent-tabs-mode: s; coding: utf-8 -*-

# This is the InternetX autoDNS json api wrapper for acme.sh
# Author: auerswald@gmail.com
# Created: 2023-02-28
#
# Before using this script for the first time do this on the console:
#
# export AUTODNS_USER="username"
# export AUTODNS_PASSWORD="password"
# export AUTODNS_CONTEXT="context"
#
# Usage: acme.sh --issue --dns dns_autodns_json -d example.com

AUTODNS_API="https://api.autodns.com/v1"

# Arguments:
#   txtdomain
#   txt
dns_autodns_json_add() {
  fulldomain="$1"
  txtvalue="$2"

  AUTODNS_USER="${AUTODNS_USER:-$(_readaccountconf_mutable AUTODNS_USER)}"
  AUTODNS_PASSWORD="${AUTODNS_PASSWORD:-$(_readaccountconf_mutable AUTODNS_PASSWORD)}"
  AUTODNS_CONTEXT="${AUTODNS_CONTEXT:-$(_readaccountconf_mutable AUTODNS_CONTEXT)}"

  if [ -z "$AUTODNS_USER" ] || [ -z "$AUTODNS_CONTEXT" ] || [ -z "$AUTODNS_PASSWORD" ]; then
    _err "You don't specify autodns user, password and context."
    return 1
  fi

  _saveaccountconf_mutable AUTODNS_USER "$AUTODNS_USER"
  _saveaccountconf_mutable AUTODNS_PASSWORD "$AUTODNS_PASSWORD"
  _saveaccountconf_mutable AUTODNS_CONTEXT "$AUTODNS_CONTEXT"

  if ! _get_autodns_zone "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _info "Adding TXT record..."

  _post_data="{\"adds\":[{\"name\":\"$_autodns_sub_domain\",\"ttl\":600,\"type\":\"TXT\",\"value\":\"$txtvalue\"}]}"
  _response="$(dns_autodns_api_call "/zone/$_autodns_zone/_stream" "$_post_data")"

  if [ "$?" -eq "0" ] && _contains "$_response" '{"type":"Zone","summary":1}'; then
    _info "Added, OK"
    return 0
  fi

  return 1
}

# Arguments:
#   txtdomain
#   txt
dns_autodns_json_rm() {
  fulldomain="$1"
  txtvalue="$2"

  AUTODNS_USER="${AUTODNS_USER:-$(_readaccountconf_mutable AUTODNS_USER)}"
  AUTODNS_PASSWORD="${AUTODNS_PASSWORD:-$(_readaccountconf_mutable AUTODNS_PASSWORD)}"
  AUTODNS_CONTEXT="${AUTODNS_CONTEXT:-$(_readaccountconf_mutable AUTODNS_CONTEXT)}"


  if ! _get_autodns_zone "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _info "Remove previous added TXT record..."
  _post_data="{\"rems\":[{\"name\":\"$_autodns_sub_domain\",\"type\":\"TXT\",\"value\":\"$txtvalue\"}]}"
  _response="$(dns_autodns_api_call "/zone/$_autodns_zone/_stream" "$_post_data")"

  if [ "$?" -eq "0" ] && _contains "$_response" '{"type":"Zone","summary":1}'; then
    _info "Deleted, OK"
    return 0
  fi

  return 1
}


dns_autodns_api_call() {
  _api_route="$1"
  _post_data="$2"

  _basic_auth=$(printf "%s:%s" "$AUTODNS_USER" "$AUTODNS_PASSWORD" | _base64)

  # @see https://help.internetx.com/display/APIXMLEN/Authentication#Authentication-AuthenticationviaCredentials(username/password/context)
  export _H1="Authorization: Basic $_basic_auth"
  export _H2="X-Domainrobot-Context: $AUTODNS_CONTEXT"

  # @see https://help.internetx.com/display/APIXMLEN/JSON+API+Basics
  #      "The use of a UserAgent is mandatory for the correct use of the JSON API."
  export _H3="User-Agent: acme.sh/${VER}"

  export _H4="Content-Type: application/json"

  _response="$(_post "$_post_data" "${AUTODNS_API}${_api_route}")"
  _debug "$_response"

  if ! _contains "$_response" '"type":"SUCCESS"'; then
    _err "$_response"
    return 1
  fi

  printf "%s" "$_response"
}

# Arguments:
#   fulldomain
# Returns:
#   _sub_domain=_acme-challenge.xxx
#   _zone=domain.tld
#   _system_ns
_get_autodns_zone() {
  domain="$1"
  i=2
  p=1

  _debug "First detect the root zone..."

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi

    _post_data="{\"view\":{\"children\":1},\"filters\":[{\"key\":\"name\",\"operator\":\"EQUAL\",\"value\":\"$h\"}]}"
    _response="$(dns_autodns_api_call "/zone/_search" "$_post_data")"

    if [ "$?" -ne "0" ]; then
      _err "invalid domain"
      return 1
    fi

    if _contains "$_response" '{"type":"Zone","summary":1}' >/dev/null; then
      _autodns_zone="$(echo "$_response" | _json_decode | _egrep_o '"origin":"[^"]*"' | cut -d : -f 2 | tr -d '"')"
      _autodns_sub_domain="$(printf "%s" "$domain" | cut -d . -f 1-$p)"

      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}
