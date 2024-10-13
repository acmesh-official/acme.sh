#!/usr/bin/env sh

# updater for the (experimental) API of myloc.de / webtropia.com
# usage: acme.sh --issue -d example.com --dns dns_myapi
# API documentation at https://apidoc.myloc.de/
# As the API does not support quering available zones yet, the zone for a given
# domain needs to be guessed. When using a subdomain, e.g. sub1.example.com,
# the zone needs to be given via the MYLOC_zone environment variable.

# Environment variables:
# export MYLOC_token=aabbccddeeffgghhiijjkkllmmnnjjkkllmmnnooppqqrrsstt
# export MYLOC_zone=example.com

myloc="https://zkm.myloc.de/api"

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_myloc_add() {
  fulldomain=$1
  txtvalue=$2

  token="${MYLOC_token:-$(_readaccountconf_mutable MYLOC_token)}"
  zone="${MYLOC_zone:-$(_readaccountconf_mutable MYLOC_zone)}"

  # the API does not provide an interface to get available zones yet
  # if no zone is set in the configuration, try to guess it from $fulldomain
  zone="$(_guess_zone "$fulldomain" "$zone")"

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $token"

  _debug "Getting records"
  response="$(_get "${myloc}/dns/zone/${zone}")"

  if _contains "$response" "error" || ! _contains "$response" "content"; then
    _err "Failed to query zone records"
    _debug "$response"
    return 1
  fi

  # save token and zone if the previous request was successful
  _savedomainconf MYLOC_token "$token"
  _savedomainconf MYLOC_zone "$zone"

  # records="$(_extract_txt_records "$response" "$fulldomain" | head -1)"
  # _debug "existing record $record"
  # if [ "$record" ]; then
  #   _info "Record for $fulldomain already exists, trying to remove it first"
  #   response="$(_post "$record" "${myloc}/dns/zone/${zone}" "" "DELETE")"
  #   if [ $? -ne 0 ]; then
  #     _info "Failed to delete record, continueing anyway"
  #   fi
  # fi

  _info "Adding record"
  record="{\"type\":\"TXT\",\"name\":\"${fulldomain}\",\"content\":\"${txtvalue}\",\"ttl\":60}"
  _debug "add record $record"
  response="$(_post "$record" "${myloc}/dns/zone/${zone}" "" "PUT")"
  _debug "add response $response"
  if [ $? -eq 0 ]; then
    if _contains "$response" "error" || _contains "$response" "unexpected"; then
      _err "Add txt record api error."
      return 1
    elif [ -z "$response" ]; then
      _info "Empty response, OK"
      return 0
    else
      _err "Add txt record unknown response."
      return 1
    fi
  fi
  _err "Add txt record curl error."
  return 1
}

#fulldomain txtvalue
dns_myloc_rm() {
  fulldomain=$1
  txtvalue=$2

  token="${MYLOC_token:-$(_readaccountconf_mutable MYLOC_token)}"
  zone="${MYLOC_zone:-$(_readaccountconf_mutable MYLOC_zone)}"

  # the API does not provide an interface to get available zones yet
  # if no zone is set in the configuration, try to guess it from $fulldomain
  zone="$(_guess_zone "$fulldomain" "$zone")"

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $token"

  _debug "Getting records"
  response="$(_get "${myloc}/dns/zone/${zone}")"

  if _contains "$response" "error" || ! _contains "$response" "content"; then
    _err "Failed to query zone records"
    _debug "$response"
    return 1
  fi

  # save token and zone if the previous request was successful
  _savedomainconf MYLOC_token "$token"
  _savedomainconf MYLOC_zone "$zone"

  records="$(_extract_txt_records "$response" "$fulldomain")"
  for record in $records; do
    _info "Deleting record for $fulldomain"
    _debug "delete record $record"
    response="$(_post "$record" "${myloc}/dns/zone/${zone}" "" "DELETE")"
    _debug "delete response $response"
    if [ $? -ne 0 ] || [ "$response" ]; then
      _info "Failed to delete record, continueing anyway"
    fi
  done

  return 0
}

# Usage: _extract_txt_records "{record1},{record2},{record3}" "_acme-challenge.sub1.mydomain.com"
_extract_txt_records() {
  response="$1"
  fulldomain="$2"
  echo "$response" | _egrep_o "\{\"ttl\":[0-9]+,\"type\":\"TXT\",\"name\":\"$fulldomain\.\",\"content\":\"[^}]*\"\}"
}

# Usage: _guess_zone "_acme-challenge.sub1.mydomain.com" "mydomain.com"
# mydomain.com can be omitted to guess from fulldomain
_guess_zone() {
  fulldomain="$1"
  zone="$2"
  if [ -z "$zone" ]; then
    zone="${fulldomain#_acme-challenge.}"
  fi
  echo "$zone"
}
