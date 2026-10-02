#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_myloc_info='myloc.de
Site: myloc.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_myloc
Issues: github.com/acmesh-official/acme.sh/issues/5193
Options:
 MYLOC_token API token
'

# updater for the (experimental) API of myloc.de / webtropia.com
# usage: acme.sh --issue -d example.com --dns dns_myloc --dnssleep 60
# API documentation at https://apidoc.myloc.de/
# As the API does not support quering available zones yet, the zone for a given
# fulldomain is searched recursively by removing prefixes one-by-one.

_myloc_api="https://zkm.myloc.de/api"

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_myloc_add() {
  _myloc_fulldomain=$1
  _myloc_txtvalue=$2

  _myloc_token="${MYLOC_token:-$(_readaccountconf_mutable MYLOC_token)}"
  if [ -z "$_myloc_token" ]; then
    _err "You didn't specify MYLOC_token"
    return 1
  fi

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $_myloc_token"

  _myloc_zone="$(_myloc_get_zone "$_myloc_fulldomain")"
  if [ $? -ne 0 ]; then
    return 1
  fi

  # save token if the previous request was successful
  _saveaccountconf_mutable MYLOC_token "$_myloc_token"

  _info "Adding record"
  _myloc_record="{\"type\":\"TXT\",\"name\":\"${_myloc_fulldomain}\",\"content\":\"\\\"${_myloc_txtvalue}\\\"\",\"ttl\":60}"
  _debug "add record request $_myloc_record to ${_myloc_api}/dns/zone/${_myloc_zone}"
  _myloc_response="$(_post "$_myloc_record" "${_myloc_api}/dns/zone/${_myloc_zone}" "" "PUT")"
  _myloc_status=$?
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
  _debug "add record response $_code $_myloc_response"
  if [ $_myloc_status -ne 0 ]; then
    _err "Add txt record curl error."
    return 1
  elif [ "$_code" = "204" ] && [ -z "$_myloc_response" ]; then
    _info "Add txt record success"
    return 0
  elif _contains "$_myloc_response" "error" || _contains "$_myloc_response" "unexpected"; then
    _err "Add txt record api error."
    return 1
  else
    _err "Add txt record unknown response."
    return 1
  fi
}

#_myloc_fulldomain _myloc_txtvalue
dns_myloc_rm() {
  _myloc_fulldomain=$1
  _myloc_txtvalue=$2

  _myloc_token="${MYLOC_token:-$(_readaccountconf_mutable MYLOC_token)}"
  if [ -z "$_myloc_token" ]; then
    _err "You didn't specify MYLOC_token"
    return 1
  fi

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $_myloc_token"

  _myloc_zone="$(_myloc_get_zone "$_myloc_fulldomain")"
  if [ $? -ne 0 ]; then
    return 1
  fi

  # save token if the previous request was successful
  _saveaccountconf_mutable MYLOC_token "$_myloc_token"

  _info "Deleting record for $_myloc_fulldomain"
  _myloc_record="{\"type\":\"TXT\",\"name\":\"${_myloc_fulldomain}\",\"content\":\"\\\"${_myloc_txtvalue}\\\"\"}"
  _debug "delete record $_myloc_record"
  _myloc_response="$(_post "$_myloc_record" "${_myloc_api}/dns/zone/${_myloc_zone}" "" "DELETE")"
  _myloc_status=$?
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
  _debug "delete response $_code $_myloc_response"
  if [ $_myloc_status -ne 0 ] || [ "$_code" != "204" ]; then
    _err "Failed to delete record"
    return 1
  fi

  return 0
}

# Usage: _myloc_get_zone "_acme-challenge.sub1.mydomain.com"
# Subdomains are walked until a zone is found or TLD is reached
_myloc_get_zone() {
  _myloc_zone=$1

  while [ "${_myloc_zone#*.}" != "$_myloc_zone" ]; do
    _debug "Get zone trying $_myloc_zone"
    _myloc_response="$(_get "${_myloc_api}/dns/zone/${_myloc_zone}")"
    _myloc_status=$?
    _debug "Get zone response $_myloc_response"
    _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
    if [ $_myloc_status -eq 0 ] && [ "$_code" = "200" ]; then
      _debug "Get zone success for $_myloc_zone"
      echo "${_myloc_zone}"
      return 0
    fi
    _myloc_zone="${_myloc_zone#*.}"
  done

  _err "Get zone failed for all candidates"
  return 1
}
