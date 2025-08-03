#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_vultr_info='vultr.com
Site: vultr.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_vultr
Options:
 VULTR_API_KEY API Key
Issues: github.com/acmesh-official/acme.sh/issues/2374
'

VULTR_Api="https://api.vultr.com/v2"

########  Public functions #####################
#
#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_vultr_add() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  VULTR_API_KEY="${VULTR_API_KEY:-$(_readaccountconf_mutable VULTR_API_KEY)}"
  if test -z "$VULTR_API_KEY"; then
    VULTR_API_KEY=''
    _err 'VULTR_API_KEY was not exported'
    return 1
  fi

  _saveaccountconf_mutable VULTR_API_KEY "$VULTR_API_KEY"

  _debug 'First detect the root zone'
  if ! _get_root "$fulldomain"; then
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug 'Getting txt records'
  _vultr_rest GET "domains/$_domain/records"

  if printf "%s\n" "$response" | grep -- "\"type\":\"TXT\",\"name\":\"$fulldomain\"" >/dev/null; then
    _err 'Error'
    return 1
  fi

  if ! _vultr_rest POST "domains/$_domain/records" "{\"name\":\"$_sub_domain\",\"data\":\"$txtvalue\",\"type\":\"TXT\"}"; then
    _err "$response"
    return 1
  fi

  _debug2 _response "$response"
  return 0
}

#fulldomain txtvalue
dns_vultr_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  VULTR_API_KEY="${VULTR_API_KEY:-$(_readaccountconf_mutable VULTR_API_KEY)}"
  if test -z "$VULTR_API_KEY"; then
    VULTR_API_KEY=""
    _err 'VULTR_API_KEY was not exported'
    return 1
  fi

  _saveaccountconf_mutable VULTR_API_KEY "$VULTR_API_KEY"

  _debug 'First detect the root zone'
  if ! _get_root "$fulldomain"; then
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug 'Getting txt records'
  _vultr_rest GET "domains/$_domain/records"

  if printf "%s\n" "$response" | grep -- "\"type\":\"TXT\",\"name\":\"$fulldomain\"" >/dev/null; then
    _err 'Error'
    return 1
  fi

  _record_id="$(echo "$response" | tr '{}' '\n' | grep '"TXT"' | grep -- "$txtvalue" | tr ',' '\n' | grep -i 'id' | cut -d : -f 2 | tr -d '"')"
  _debug _record_id "$_record_id"
  if [ "$_record_id" ]; then
    _info "Successfully retrieved the record id for ACME challenge."
  else
    _info "Empty record id, it seems no such record."
    return 0
  fi

  if ! _vultr_rest DELETE "domains/$_domain/records/$_record_id"; then
    _err "$response"
    return 1
  fi

  _debug2 _response "$response"
  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=1
  while true; do
    _domain=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$_domain"
    if [ -z "$_domain" ]; then
      return 1
    fi

    if ! _vultr_rest GET "domains"; then
      return 1
    fi

    if printf "%s\n" "$response" | grep -E '^\{.*\}' >/dev/null; then
      if _contains "$response" "\"domain\":\"$_domain\""; then
        _sub_domain="$(echo "$fulldomain" | sed "s/\\.$_domain\$//")"
        return 0
      else
        _debug "Go to next level of $_domain"
      fi
    else
      _err "$response"
      return 1
    fi
    i=$(_math "$i" + 1)
  done

  return 1
}

_vultr_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  api_key_trimmed=$(echo "$VULTR_API_KEY" | tr -d '"')

  export _H1="Authorization: Bearer $api_key_trimmed"
  export _H2='Content-Type: application/json'

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$VULTR_Api/$ep" "" "$m")"
  else
    response="$(_get "$VULTR_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "Error $ep"
    return 1
  fi

  _debug2 response "$response"
  return 0
}
