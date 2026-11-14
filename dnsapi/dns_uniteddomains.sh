#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_uniteddomains_info='United Domains (united-domains.de) DNS hosting API
Site: united-domains.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_uniteddomains
Options:
 UNITEDDOMAINS_USER Username of the united-domains account
 UNITEDDOMAINS_PASSWORD Password of the united-domains account
Issues: github.com/acmesh-official/acme.sh/issues/6815
'

UNITEDDOMAINS_Api="${UNITEDDOMAINS_Api:-https://dnsapi.ud-group.de}"
_ud_token=""

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_uniteddomains_add() {
  fulldomain="$(_idn "$1")"
  txtvalue=$2

  if ! _uniteddomains_login; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _uniteddomains_get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _info "Adding record"
  _ud_data="{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"value\":\"$txtvalue\",\"ttl\":60}"
  if ! _uniteddomains_rest POST "dns/zones/$_ud_zone_id/records" "$_ud_data"; then
    _err "Add txt record error."
    return 1
  fi

  if [ -n "$response" ] && ! _contains "$response" "$txtvalue"; then
    _err "Add txt record error: unexpected response."
    return 1
  fi

  if ! _uniteddomains_activate; then
    return 1
  fi

  _info "Added, OK"
  return 0
}

#Usage: rm  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_uniteddomains_rm() {
  fulldomain="$(_idn "$1")"
  txtvalue=$2

  if ! _uniteddomains_login; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _uniteddomains_get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug "Getting txt records"
  if ! _uniteddomains_rest GET "dns/zones/$_ud_zone_id/records"; then
    _err "Error querying records"
    return 1
  fi

  _debug "Detect the record id"
  if ! _uniteddomains_find_record_id "$fulldomain" "$txtvalue"; then
    return 1
  fi

  if [ -z "$_ud_record_id" ]; then
    _info "Record not available"
    return 0
  fi

  _debug "Removing txt record"
  if ! _uniteddomains_rest DELETE "dns/zones/$_ud_zone_id/records/$_ud_record_id"; then
    _err "Cannot remove record"
    return 1
  fi

  if ! _uniteddomains_activate; then
    return 1
  fi

  _info "Removed, OK"
  return 0
}

####################  Private functions below ##################################

#Usage: username password
#returns
# _ud_token  the session token
_uniteddomains_login() {
  UNITEDDOMAINS_USER="${UNITEDDOMAINS_USER:-$(_readaccountconf_mutable UNITEDDOMAINS_USER)}"
  UNITEDDOMAINS_PASSWORD="${UNITEDDOMAINS_PASSWORD:-$(_readaccountconf_mutable UNITEDDOMAINS_PASSWORD)}"
  if [ -z "$UNITEDDOMAINS_USER" ] || [ -z "$UNITEDDOMAINS_PASSWORD" ]; then
    UNITEDDOMAINS_USER=""
    UNITEDDOMAINS_PASSWORD=""
    _err "You didn't specify a united-domains username and password yet."
    _err "Please set UNITEDDOMAINS_USER and UNITEDDOMAINS_PASSWORD and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable UNITEDDOMAINS_USER "$UNITEDDOMAINS_USER"
  _saveaccountconf_mutable UNITEDDOMAINS_PASSWORD "$UNITEDDOMAINS_PASSWORD"

  _info "Getting session token"
  _ud_user=$(printf "%s" "$UNITEDDOMAINS_USER" | sed 's/\\/\\\\/g; s/"/\\"/g')
  _ud_pass=$(printf "%s" "$UNITEDDOMAINS_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')
  if ! _uniteddomains_rest POST "login" "{\"username\":\"$_ud_user\",\"password\":\"$_ud_pass\"}"; then
    _err "Login failed."
    return 1
  fi

  _ud_token=$(printf "%s" "$response" | _egrep_o '"token": *"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
  if [ -z "$_ud_token" ]; then
    _err "Cannot get session token from response."
    return 1
  fi
  return 0
}

#_acme-challenge.www.domain.com
#returns
# _ud_domain=domain.com
# _ud_zone_id=zone id of domain.com
_uniteddomains_get_root() {
  domain=$1
  i=1
  p=0
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _uniteddomains_rest GET "dns/zones?name=$h"; then
      _ud_zone_id=$(printf "%s" "$response" | _normalizeJson | tr '{' '\n' | grep "\"name\": *\"$h\"" | _head_n 1 | _egrep_o '"id": *("[^"]*"|[0-9]+)' | _head_n 1 | sed 's/^"id": *//' | tr -d '"')
    else
      _debug "zones lookup by name failed, falling back to domain lookup"
      if ! _uniteddomains_rest GET "domains?name=$h"; then
        return 1
      fi
      _ud_domain_id=$(printf "%s" "$response" | _normalizeJson | tr '{' '\n' | grep "\"name\": *\"$h\"" | _head_n 1 | _egrep_o '"id": *("[^"]*"|[0-9]+)' | _head_n 1 | sed 's/^"id": *//' | tr -d '"')
      if [ -z "$_ud_domain_id" ]; then
        _debug "no matching domain for $h"
        p="$i"
        i=$(_math "$i" + 1)
        continue
      fi
      if ! _uniteddomains_rest GET "dns/zones?domainId=$_ud_domain_id"; then
        return 1
      fi
      _ud_zone_id=$(printf "%s" "$response" | _normalizeJson | tr '{' '\n' | grep "\"name\": *\"$h\"" | _head_n 1 | _egrep_o '"id": *("[^"]*"|[0-9]+)' | _head_n 1 | sed 's/^"id": *//' | tr -d '"')
      if [ -z "$_ud_zone_id" ]; then
        _ud_zone_id=$(printf "%s" "$response" | _normalizeJson | _egrep_o '"id": *("[^"]*"|[0-9]+)' | _head_n 1 | sed 's/^"id": *//' | tr -d '"')
      fi
    fi

    if [ -n "$_ud_zone_id" ]; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _ud_domain="$h"
      _debug _sub_domain "$_sub_domain"
      _debug _ud_domain "$_ud_domain"
      _debug _ud_zone_id "$_ud_zone_id"
      return 0
    fi

    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

#Usage: fulldomain txtvalue
#returns
# _ud_record_id  id of the matching TXT record, empty if none
_uniteddomains_find_record_id() {
  _ud_name=$1
  _ud_value=$2
  _ud_record_id=""

  _ud_name_re=$(printf "%s" "$_ud_name" | sed 's/[.]/\\./g')
  _ud_record_line=$(printf "%s" "$response" | _normalizeJson | tr '{' '\n' | grep "\"type\": *\"TXT\"" | grep "\"name\": *\"${_ud_name_re}\\.\\?\"" | grep "\"value\": *\"$_ud_value\"" | _head_n 1)
  if [ -n "$_ud_record_line" ]; then
    _ud_record_id=$(printf "%s" "$_ud_record_line" | _egrep_o '"id": *("[^"]*"|[0-9]+)' | _head_n 1 | sed 's/^"id": *//' | tr -d '"')
  fi
  _debug _ud_record_id "$_ud_record_id"
  return 0
}

#Activate the zone so that staged changes are published
_uniteddomains_activate() {
  _info "Activating zone to publish changes"
  if ! _uniteddomains_rest POST "dns/zones/$_ud_zone_id/activate" ""; then
    _err "Error activating zone. Please activate the zone in the united-domains control panel."
    return 1
  fi
  return 0
}

_uniteddomains_rest() {
  _ud_m=$1
  _ud_ep="$2"
  _ud_data="$3"
  _debug "$_ud_ep"

  export _H1="Authorization: Bearer $_ud_token"
  export _H2="Content-Type: application/json"

  _debug data "$_ud_data"
  if [ "$_ud_m" = "GET" ]; then
    response="$(_get "$UNITEDDOMAINS_Api/$_ud_ep")"
  else
    response="$(_post "$_ud_data" "$UNITEDDOMAINS_Api/$_ud_ep" "" "$_ud_m")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $_ud_ep: request failed"
    return 1
  fi

  _ud_code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_ud_code"

  case "$_ud_code" in
  2??) ;;
  *)
    _err "error $_ud_ep: HTTP $_ud_code $response"
    return 1
    ;;
  esac

  _debug2 response "$response"
  return 0
}
