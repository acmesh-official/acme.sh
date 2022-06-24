#!/usr/bin/env #!/bin/sh

# Author: Mohammad Ali Sarbanha <sarbanha at yahoo dot com>
# Repository: https://github.com/sarbanha/acme.sh-dnsapi-dns_arvancdn

# export ARVAN_API_KEY="-----------"

ARVAN_CDN_API="https://napi.arvancloud.com/cdn/4.0"

#Usage: dns_arvancdn_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_arvancdn_add() {

  fulldomain=$1
  challenge=$2
  zone=${fulldomain:16}

  _debug "dns_arvan_add(): Started"

  ARVAN_API_KEY="${ARVAN_API_KEY:-$(_readaccountconf_mutable ARVAN_API_KEY)}"
  if [ -z $ARVAN_API_KEY ]; then
    ARVAN_API_KEY=""
    _err "dns_arvan_add(): ARVAN_API_KEY has not been defined yet."
    _err "dns_arvan_add(): export ARVAN_API_KEY=\"---YOUR-API-KEY---\""
    return 1
  fi
  _saveaccountconf_mutable ARVAN_API_KEY "$ARVAN_API_KEY"

  _debug "dns_arvan_add(): Check domain root zone availability for $zone"
  if ! _get_root $zone; then
    _err "dns_arvan_add(): Invalid domain $zone"
    return 1
  fi

  _debug "dns_arvan_add(): fulldomain $fulldomain"
  _debug "dns_arvan_add(): textvalue $challenge"
  _debug "dns_arvan_add(): domain $zone"

  _record_add $zone $challenge

}

#Usage: dns_arvancdn_rm fulldomain txtvalue
dns_arvancdn_rm(){

  fulldomain=$1
  challenge=$2
  zone=${fulldomain:16}

  ARVAN_API_KEY="${ARVAN_API_KEY:-$(_readaccountconf_mutable ARVAN_API_KEY)}"
  if [ -z $ARVAN_API_KEY ]; then
    ARVAN_API_KEY=""
    _err "dns_arvan_rm(): ARVAN_API_KEY has not been defined yet."
    _err "dns_arvan_rm(): export ARVAN_API_KEY=\"---YOUR-API-KEY---\""
    return 1
  fi

  record_id=$(_record_get_id $zone $challenge)

  _record_remove $zone $record_id

}

####################
# Private functions
####################

#Usage: _get_root zone
_get_root(){
  _zone=$1

  export _H1="Content-Type: application-json"
  export _H2="Authorization: apikey $ARVAN_API_KEY"

  _response=$(_get $ARVAN_CDN_API/domains/$_zone)
  _debug2 "_get_root()" $_response
  _debug2 "_get_root()" $_zone
  if _contains "$_response" "$_zone"; then
    # is valid
    _valid=0
  else
    # is not valid
    _valid=1
  fi

  return $_valid
}

#Usage: _record_add zone challenge
_record_add(){
  zone=$1
  challenge=$2

  export _H1="Content-Type: application-json"
  export _H2="Authorization: apikey $ARVAN_API_KEY"

  payload="{\"type\":\"txt\",\"name\":\"_acme-challenge\",\"cloud\":false,\"value\":{\"text\":\"$challenge\"},\"ttl\":120}"
  _response=$(_post "$payload" "$ARVAN_CDN_API/domains/$zone/dns-records" "" "POST" "application/json" | _base64)

  _debug2 "_record_add(): " $_response
  _debug2 "      Payload: " $payload
}

#Usage: _record_get_id zone challenge
_record_get_id(){

  zone=$1
  challenge=$2

  export _H1="Content-Type: application-json"
  export _H2="Authorization: apikey $ARVAN_API_KEY"

  _response=$(_get $ARVAN_CDN_API/domains/$zone/dns-records/?type=txt\&search=$challenge | _json_decode | _normalizeJson | grep -Eo '"id":.*?,"value":\{"text":".*?"\}' | sed 's/"id":"\([^"]*\)".*/\1/')
  _debug2 "_record_get_id(): " $_response


  echo "$_response"

}

#Usage: _record_remove zone record_id
_record_remove(){

  zone=$1
  record_id=$2

  export _H1="Content-Type: application-json"
  export _H2="Authorization: apikey $ARVAN_API_KEY"

  _response=$(_post "" $ARVAN_CDN_API/domains/$zone/dns-records/$record_id "" "DELETE" "application/json")

  _debug  "_record_remove(): ACME Challenge Removed"
  _debug2 "        Response: " $_response

}
