#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_muumuu_info='muumuu-domain.com
Site: muumuu-domain.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_muumuu
Options:
 MUUMUU_PAT Personal Access Token (scopes: domains:read, dns:read, dns:write)
Issues: github.com/acmesh-official/acme.sh/issues
'

MUUMUU_API="https://muumuu-domain.com/api/v2"

########  Public functions #####################

dns_muumuu_add() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue="$2"

  _info "Using muumuu-domain.com DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  MUUMUU_PAT="${MUUMUU_PAT:-$(_readaccountconf_mutable MUUMUU_PAT)}"
  if [ -z "$MUUMUU_PAT" ]; then
    _err "MUUMUU_PAT is not set."
    _err "Please create a Personal Access Token at https://muumuu-domain.com"
    _err "with scopes: domains:read, dns:read, dns:write"
    return 1
  fi
  _saveaccountconf_mutable MUUMUU_PAT "$MUUMUU_PAT"

  if ! _muumuu_get_root "$fulldomain"; then
    _err "Unable to find the root domain for $fulldomain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding TXT record for ${fulldomain}"
  body="{\"fqdn\":\"${fulldomain}.\",\"type\":\"TXT\",\"value\":\"${txtvalue}\",\"ttl\":3600}"
  if _muumuu_rest POST "/me/domains/${_domain_id}/dns-records" "$body"; then
    if [ "$_code" = "201" ]; then
      _info "TXT record added successfully"
      return 0
    fi
  fi

  _err "Failed to add TXT record (HTTP ${_code})"
  return 1
}

dns_muumuu_rm() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue="$2"

  _info "Using muumuu-domain.com DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  MUUMUU_PAT="${MUUMUU_PAT:-$(_readaccountconf_mutable MUUMUU_PAT)}"
  if [ -z "$MUUMUU_PAT" ]; then
    _err "MUUMUU_PAT is not set."
    return 1
  fi

  if ! _muumuu_get_root "$fulldomain"; then
    _err "Unable to find the root domain for $fulldomain"
    return 1
  fi
  _debug _domain_id "$_domain_id"

  _info "Looking up TXT record for ${fulldomain}"
  if ! _muumuu_rest GET "/me/domains/${_domain_id}/dns-records?type=TXT&fqdn=${fulldomain}."; then
    _err "Failed to list TXT records"
    return 1
  fi

  record_id=$(echo "$response" | _egrep_o "\"id\":[0-9]+[^}]*\"value\":\"${txtvalue}\"" | _egrep_o "\"id\":[0-9]+" | cut -d: -f2)
  if [ -z "$record_id" ]; then
    _info "TXT record not found, nothing to remove"
    return 0
  fi
  _debug record_id "$record_id"

  if _muumuu_rest DELETE "/me/domains/${_domain_id}/dns-records/${record_id}"; then
    if [ "$_code" = "204" ]; then
      _info "TXT record deleted successfully"
      return 0
    fi
  fi

  _err "Failed to delete TXT record (HTTP ${_code})"
  return 1
}

####################  Private functions below ##################################

#  _acme-challenge.www.example.com
# sets:
#  _domain_id   MU00000001
#  _sub_domain  _acme-challenge.www
#  _domain      example.com
_muumuu_get_root() {
  domain="$1"
  i=1
  p=0
  h=""
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      return 1
    fi
    if ! _muumuu_rest GET "/me/domains?fqdn=${h}&page-size=1"; then
      return 1
    fi
    if [ "$_code" = "401" ] || [ "$_code" = "403" ]; then
      _err "Authentication failed (HTTP ${_code}). Check MUUMUU_PAT."
      return 1
    fi
    if _contains "$response" "\"fqdn\":\"${h}\""; then
      _domain_id=$(echo "$response" | _egrep_o "\"id\":\"MU[0-9]+\"" | _head_n 1 | cut -d: -f2 | tr -d '"')
      _domain="$h"
      if [ "$p" = "0" ]; then
        _sub_domain=""
      else
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      fi
      return 0
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
}

_muumuu_rest() {
  _method="$1"
  _path="$2"
  _data="$3"
  _url="${MUUMUU_API}${_path}"

  export _H1="Authorization: Bearer ${MUUMUU_PAT}"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  _secure_debug2 data "$_data"

  if [ "$_method" = "GET" ]; then
    response="$(_get "$_url")"
  else
    response="$(_post "$_data" "$_url" "" "$_method")"
  fi
  _ret="$?"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "HTTP code: ${_code}"
  _secure_debug2 response "$response"

  if [ "$_ret" != "0" ]; then
    _err "Error accessing ${_url}"
    return 1
  fi

  response="$(printf "%s" "$response" | _normalizeJson)"
  return 0
}
