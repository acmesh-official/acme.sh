#!/usr/bin/env bash

# Author: Mohammad Ali Sarbanha <sarbanha at yahoo dot com>
# Repository: https://github.com/sarbanha/acme.sh-dnsapi-dns_arvancdn

# export ARVAN_API_KEY="-----------"

ARVAN_CDN_API="https://napi.arvancloud.com/cdn/4.0"

#Usage: dns_arvancdn_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_arvancdn_add() {

  _fulldomain=$1
  _challenge=$2

  _debug "dns_arvan_add(): Started"

  ARVAN_API_KEY="${ARVAN_API_KEY:-$(_readaccountconf_mutable ARVAN_API_KEY)}"
  if [ -z "${ARVAN_API_KEY}" ]; then
    ARVAN_API_KEY=""
    _err "dns_arvan_add(): ARVAN_API_KEY has not been defined yet."
    _err "dns_arvan_add(): export ARVAN_API_KEY=\"---YOUR-API-KEY---\""
    return 1
  fi
  _saveaccountconf_mutable ARVAN_API_KEY "${ARVAN_API_KEY}"

  _debug "dns_arvan_add(): Check domain root zone availability for ${_fulldomain}"

  if ! _zone=$(_get_root "${_fulldomain}"); then
    _err "dns_arvan_add(): Root zone for ${_fulldomain} not found!"
    return 1
  fi

  #_record_name=$(echo "${_zone}" | sed "s/\.\..*//")
  _record_name=${_zone/\.\.*/}
  #_zone=$(echo "${_zone}" | sed "s/.*\.\.//")
  _zone=${_zone/*\.\./}

  _debug "dns_arvan_add(): fulldomain ${_fulldomain}"
  _debug "dns_arvan_add(): textvalue ${_challenge}"
  _debug "dns_arvan_add(): domain ${_record_name}"
  _debug "dns_arvan_add(): domain ${_zone}"

  _record_add "${_record_name}" "${_zone}" "${_challenge}"

}

#Usage: dns_arvancdn_rm fulldomain txtvalue
dns_arvancdn_rm() {

  _fulldomain=$1
  _challenge=$2

  ARVAN_API_KEY="${ARVAN_API_KEY:-$(_readaccountconf_mutable ARVAN_API_KEY)}"
  if [ -z "${ARVAN_API_KEY}" ]; then
    ARVAN_API_KEY=""
    _err "dns_arvan_rm(): ARVAN_API_KEY has not been defined yet."
    _err "dns_arvan_rm(): export ARVAN_API_KEY=\"---YOUR-API-KEY---\""
    return 1
  fi

  if ! _zone=$(_get_root "${_fulldomain}"); then
    _err "dns_arvan_rm(): Root zone for ${_fulldomain} not found!"
    return 1
  fi

  #_record_name=$(echo "${_zone}" | sed "s/\.\..*//")
  _record_name=${_zone/\.\.*/}
  #_zone=$(echo "${_zone}" | sed "s/.*\.\.//")
  _zone=${_zone/*\.\./}

  _record_id=$(_record_get_id "${_zone}" "${_challenge}")

  _record_remove "${_zone}" "${_record_id}"

}

####################
# Private functions
####################

#Usage: _get_root zone
_get_root() {
  _fulldomain=$1
  _zone=$_fulldomain

  export _H1="Content-Type: application-json"
  export _H2="Authorization: apikey ${ARVAN_API_KEY}"

  _response=$(_get "${ARVAN_CDN_API}/domains")
  #_domains_list=( $( echo "${_response}" | grep -Poe '"domain":"[^"]*"' | sed 's/"domain":"//' | sed 's/"//') )
  read -r -a _domains_list < <(echo "${_response}" | grep -Poe '"domain":"[^"]*"' | sed 's/"domain":"//' | sed 's/"//')

  _debug2 "_get_root(): reponse ${_response}"
  _debug2 "_get_root(): domains list ${_domains_list[*]}"

  #Fibding a matching Zone
  while [[ -n "${_zone}" ]]; do
    for tmp in "${_domains_list[@]}"; do
      if [ "${tmp}" = "${_zone}" ]; then
        break 2
      fi
    done
    _zone=$(sed 's/^[^.]*\.\?//' <(echo "${_zone}"))
  done
  if [ -z "${_zone}" ]; then
    _debug2 "_get_root(): Zone not found on provider"
    exit 1
  fi

  _marked_zone=$(sed "s/^\(.*\)\.\(${_zone}\)$/\1..\2/" <(echo "${_fulldomain}"))
  echo "${_marked_zone}"

}

#Usage: _record_add record_name zone challenge
_record_add() {

  _record_name=$1
  _zone=$2
  _challenge=$3

  export _H1="Content-Type: application-json"
  export _H2="Authorization: apikey ${ARVAN_API_KEY}"

  _payload="{\"type\":\"txt\",\"name\":\"${_record_name}\",\"cloud\":false,\"value\":{\"text\":\"${_challenge}\"},\"ttl\":120}"
  _response=$(_post "${_payload}" "${ARVAN_CDN_API}/domains/${_zone}/dns-records" "" "POST" "application/json" | _base64)

  _debug2 "_record_add(): ${_response}"
  _debug2 "      Payload: ${_payload}"
}

#Usage: _record_get_id zone challenge
_record_get_id() {

  _zone=$1
  _challenge=$2

  export _H1="Content-Type: application-json"
  export _H2="Authorization: apikey ${ARVAN_API_KEY}"

  _response=$(_get "${ARVAN_CDN_API}/domains/${_zone}/dns-records/?type=txt\&search=${_challenge}" | _json_decode | _normalizeJson | grep -Eo '"id":.*?,"value":\{"text":".*?"\}' | sed 's/"id":"\([^"]*\)".*/\1/')
  _debug2 "_record_get_id(): ${_response}"

  echo "${_response}"

}

#Usage: _record_remove zone record_id
_record_remove() {

  _zone=$1
  _record_id=$2

  export _H1="Content-Type: application-json"
  export _H2="Authorization: apikey $ARVAN_API_KEY"

  _response=$(_post "" "$ARVAN_CDN_API/domains/$_zone/dns-records/$_record_id" "" "DELETE" "application/json")

  _debug "_record_remove(): ACME Challenge Removed"
  _debug2 "        Response: $_response"

}
