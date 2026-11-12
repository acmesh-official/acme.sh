#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_nameocean_info='NameOcean.net
Site: NameOcean.net
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_nameocean
Options:
 NAMEOCEAN_API_KEY API key with the dns:read and dns:write scopes, from https://nameocean.net/dashboard/api/
Issues: github.com/acmesh-official/acme.sh/issues
Author: NameOcean <info@nameocean.net>
'

NAMEOCEAN_API="https://nameocean.net/api/v1"

########  Public functions #####################

#Usage: dns_nameocean_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nameocean_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _nameocean_load_key; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "No NameOcean DNS zone found for $fulldomain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if _nameocean_find_record "$txtvalue"; then
    _info "The TXT record already exists"
    return 0
  fi

  _info "Adding TXT record"
  if ! _nameocean_rest POST "dns/$_domain/records" "{\"type\":\"TXT\",\"hostname\":\"$_sub_domain\",\"text\":\"$txtvalue\",\"ttl\":\"5m\"}"; then
    _err "Could not add the TXT record: $response"
    return 1
  fi
  if ! _contains "$response" "\"id\""; then
    _err "Could not add the TXT record: $response"
    return 1
  fi
  _info "Added, OK"
  return 0
}

#Usage: dns_nameocean_rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nameocean_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _nameocean_load_key; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "No NameOcean DNS zone found for $fulldomain"
    return 1
  fi

  if ! _nameocean_find_record "$txtvalue"; then
    _info "The TXT record is already gone"
    return 0
  fi
  _debug record_id "$_record_id"

  if ! _nameocean_rest DELETE "dns/$_domain/records/TXT/$_record_id"; then
    _err "Could not delete the TXT record: $response"
    return 1
  fi
  _info "Removed, OK"
  return 0
}

####################  Private functions below ##################################

_nameocean_load_key() {
  NAMEOCEAN_API_KEY="${NAMEOCEAN_API_KEY:-$(_readaccountconf_mutable NAMEOCEAN_API_KEY)}"
  if [ -z "$NAMEOCEAN_API_KEY" ]; then
    NAMEOCEAN_API_KEY=""
    _err "You didn't specify a NameOcean API key yet."
    _err "Create one with the dns:read and dns:write scopes at https://nameocean.net/dashboard/api/"
    return 1
  fi
  _saveaccountconf_mutable NAMEOCEAN_API_KEY "$NAMEOCEAN_API_KEY"
  return 0
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# response = the records of the zone
_get_root() {
  domain=$1
  i=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi
    # the zone's own records answer 200; a name that is not a zone of the account, 404
    if _nameocean_rest GET "dns/$h/records" && _contains "$response" "\"records\""; then
      _domain=$h
      _sub_domain=$(printf "%s" "$domain" | sed "s/\\.$_domain\$//")
      if [ "$_sub_domain" = "$_domain" ]; then
        _sub_domain="@"
      fi
      return 0
    fi
    i=$(_math "$i" + 1)
  done
}

# Looks for the TXT record $_sub_domain = $1 in $response (the zone's records).
# Sets _record_id.
_nameocean_find_record() {
  _record_id=$(printf "%s" "$response" | tr -d "\n" | tr "{" "\n" | grep "\"type\": *\"TXT\"" | grep "\"hostname\": *\"$_sub_domain\"" | grep -F -- "\"$1\"" | _egrep_o "\"id\": *[0-9]+" | _head_n 1 | tr -d "\" " | cut -d : -f 2)
  [ -n "$_record_id" ]
}

_nameocean_rest() {
  m=$1
  ep=$2
  data=$3

  export _H1="Authorization: Bearer $NAMEOCEAN_API_KEY"
  export _H2="Accept: application/json"

  if [ "$m" = "GET" ]; then
    response="$(_get "$NAMEOCEAN_API/$ep")"
  else
    _debug data "$data"
    response="$(_post "$data" "$NAMEOCEAN_API/$ep" "" "$m" "application/json")"
  fi
  ret=$?
  _debug2 response "$response"
  if [ "$ret" != "0" ]; then
    _err "error $m $ep"
    return 1
  fi
  # errors come back as {"error": "...", "code": "..."}
  if _contains "$response" "\"error\""; then
    return 1
  fi
  return 0
}
