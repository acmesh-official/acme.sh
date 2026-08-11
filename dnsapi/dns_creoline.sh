#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_creoline_info='creoline
Site: https://www.creoline.com/de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_creoline
Help: https://help.creoline.com
Options:
 creolineApiToken
 creolineApiSecret
Issues: github.com/acmesh-official/acme.sh/issues/7103
'

creolineApi="https://api.creoline.com/v1"

########  Public functions #####################

# Usage: add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPB8"
dns_creoline_add() {
  fulldomain=$1
  txtvalue=$2

  creolineApiToken="${creolineApiToken:-$(_readaccountconf_mutable creolineApiToken)}"
  creolineApiSecret="${creolineApiSecret:-$(_readaccountconf_mutable creolineApiSecret)}"

  if [ -z "$creolineApiToken" ] || [ -z "$creolineApiSecret" ]; then
    _err "Error required creoline API Token or creoline API Secret not specified."
    _err "Please set it with the Command 'export creolineApiToken=<YourToken>' and 'export creolineApiSecret=<YourSecret>'."
    return 1
  else
    _saveaccountconf_mutable creolineApiToken "$creolineApiToken"
    _saveaccountconf_mutable creolineApiSecret "$creolineApiSecret"
  fi

  _debug "Detecting the root dns zone."
  if ! _get_root "$fulldomain"; then
    _err "Error on detecting the root dns zone."
    return 1
  fi

  _info "Adding record"
  if _creoline_rest POST "dns/zone/$_domain/record" "{\"type\":\"TXT\",\"host\":\"$_sub_domain\",\"record\":\"$txtvalue\",\"ttl\":\"60\"}"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1
}

#fulldomain txtvalue
dns_creoline_rm() {
  fulldomain=$1
  txtvalue=$2

  creolineApiToken="${creolineApiToken:-$(_readaccountconf_mutable creolineApiToken)}"
  creolineApiSecret="${creolineApiSecret:-$(_readaccountconf_mutable creolineApiSecret)}"

  _debug "Detecting the root dns zone."
  if ! _get_root "$fulldomain"; then
    _err "Error on detecting the root dns zone."
    return 1
  fi

  _info "Getting earlier created txt record."
  if ! _creoline_rest GET "dns/zone/$_domain/record/type/TXT/record/$txtvalue"; then
    if _contains "$response" "errors" || _contains "$response" "message"; then
      _err "Error on getting earlier created txt record."
      return 1
    fi
    _err "Error on getting earlier created txt record."
    return 1
  fi

  record_id=$(echo "$response" | _egrep_o "\"id\"[ ]*:[ ]*[0-9]+" | cut -d : -f 2 | tr -d \" | _head_n 1 | tr -d " ")
  _debug "record_id" "$record_id"

  if [ -z "$record_id" ]; then
    _err "Error on deleting earlier created txt record. No record id found in response."
    return 1
  fi

  _info "Deleting earlier created txt record."
  if ! _creoline_rest DELETE "dns/zone/$_domain/record/$record_id"; then
    if _contains "$response" "errors" || _contains "$response" "message"; then
      _err "Error on deleting earlier created txt record."
      return 1
    fi
    _err "Error on deleting earlier created txt record."
    return 1
  fi

  _info "Deleted, OK"
  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  if ! _creoline_rest GET "dns/zone/root/$domain"; then
    return 1
  fi

  _sub_domain=$(echo "$response" | _egrep_o "\"subDomain\"[ ]*:[ ]*\"[^\"]+\"" | cut -d : -f 2 | tr -d \" | _head_n 1 | tr -d " ")
  _debug _sub_domain "$_sub_domain"

  _domain=$(echo "$response" | _egrep_o "\"domain\"[ ]*:[ ]*\"[^\"]+\"" | cut -d : -f 2 | tr -d \" | _head_n 1 | tr -d " ")
  _debug _domain "$_domain"

  if [ -z "$_domain" ] || [ -z "$_sub_domain" ]; then
    return 1
  fi
}

_creoline_rest() {
  method=$1
  uri="$2"
  data="$3"
  timestamp=$(_time)
  canonical_request="${timestamp}.${creolineApi}/${uri}"
  signature_hash=$(printf "%s" "$canonical_request" | _hmac sha256 "$(printf "%s" "$creolineApiSecret" | _hex_dump | tr -d " ")" hex)

  _debug method "$method"
  _debug uri "$uri"
  _debug data "$data"

  _debug2 timestamp "$timestamp"
  _debug2 canonical_request "$canonical_request"
  _debug2 signature_hash "$signature_hash"

  token_trimmed=$(echo "$creolineApiToken" | tr -d '"')
  hmac_trimmed=$(echo "$signature_hash" | tr -d '"')

  export _H1="Content-Type: application/json"

  if [ "$token_trimmed" ]; then
    export _H2="X-Api-Token: $token_trimmed"
  fi

  if [ "$hmac_trimmed" ]; then
    export _H3="X-Creoline-Api-Signature: $hmac_trimmed"
  fi

  if [ "$timestamp" ]; then
    export _H4="X-Creoline-Api-Timestamp: $timestamp"
  fi

  if [ "$method" != "GET" ]; then
    response="$(_post "$data" "$creolineApi/$uri" "" "$method")"
  else
    response="$(_get "$creolineApi/$uri")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $uri"
    return 1
  fi

  _debug response "$response"

  if _contains "$response" "errors"; then
    error=$(echo "$response" | _egrep_o "\"errors\":[[]*\"[^\"]+\"" | cut -d : -f 2 | tr -d \" | tr -d "[")
    _err "Error: $error"
    _err "URI:$uri"
    return 1
  elif _contains "$response" "message"; then
    message=$(echo "$response" | _egrep_o "\"message\"[ ]*:[ ]*\"[^\"]+\"" | cut -d : -f 2 | tr -d \")
    _err "Error: $message"
    _err "URI:$uri"
    return 1
  fi

  return 0
}
