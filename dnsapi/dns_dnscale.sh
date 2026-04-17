#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_dnscale_info='DNScale DNS API
 DNScale authoritative DNS hosting.
 Requires an API token with records:read and records:write scopes.
Domains: dnscale.eu
Site: dnscale.eu
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_dnscale
Options:
 DNSCALE_Token API Token. Create one at app.dnscale.eu with records:read and records:write scopes.
 DNSCALE_Api API URL. Optional. Default: https://api.dnscale.eu
'

DNSCALE_API_DEFAULT="https://api.dnscale.eu"

########  Public functions #####################

# Usage: dns_dnscale_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnscale_add() {
  fulldomain=$1
  txtvalue=$2

  DNSCALE_Token="${DNSCALE_Token:-$(_readaccountconf_mutable DNSCALE_Token)}"
  DNSCALE_Api="${DNSCALE_Api:-$(_readaccountconf_mutable DNSCALE_Api)}"

  if [ -z "$DNSCALE_Token" ]; then
    DNSCALE_Token=""
    _err "You didn't specify a DNScale API token."
    _err "Create one at https://app.dnscale.eu with records:read and records:write scopes."
    _err "Then set DNSCALE_Token and try again."
    return 1
  fi

  if [ -z "$DNSCALE_Api" ]; then
    DNSCALE_Api="$DNSCALE_API_DEFAULT"
  fi

  _saveaccountconf_mutable DNSCALE_Token "$DNSCALE_Token"
  _saveaccountconf_mutable DNSCALE_Api "$DNSCALE_Api"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain or zone not found"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _domain_id "$_domain_id"

  _info "Adding TXT record for ${fulldomain}"
  if ! _dnscale_rest POST "v1/zones/${_domain_id}/records" "{\"name\":\"${fulldomain}\",\"type\":\"TXT\",\"content\":\"${txtvalue}\",\"ttl\":120}"; then
    _err "Could not add TXT record"
    return 1
  fi

  _info "TXT record added successfully"
  return 0
}

# Usage: dns_dnscale_rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnscale_rm() {
  fulldomain=$1
  txtvalue=$2

  DNSCALE_Token="${DNSCALE_Token:-$(_readaccountconf_mutable DNSCALE_Token)}"
  DNSCALE_Api="${DNSCALE_Api:-$(_readaccountconf_mutable DNSCALE_Api)}"

  if [ -z "$DNSCALE_Token" ]; then
    DNSCALE_Token=""
    _err "You didn't specify a DNScale API token."
    return 1
  fi

  if [ -z "$DNSCALE_Api" ]; then
    DNSCALE_Api="$DNSCALE_API_DEFAULT"
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain or zone not found"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _domain_id "$_domain_id"

  _info "Deleting TXT record for ${fulldomain}"

  # List records for the zone, find the id of the matching TXT record,
  # then delete by id. The delete-by-id path is the canonical delete.
  if ! _dnscale_rest GET "v1/zones/${_domain_id}/records?limit=500"; then
    _err "Could not list records for deletion"
    return 1
  fi

  # Each record is its own JSON object; split the response on '{' so each
  # record's fields end up on one line, then filter by name, type, and
  # content. TXT content is stored quoted by PowerDNS (\"value\"), so we
  # match on the acme-challenge token value itself — unique enough to avoid
  # collisions with any other record in the zone.
  _fulldomain_dot="${fulldomain}."
  _record_id=$(echo "$response" | tr '{' '\n' \
    | grep "\"name\":\"${_fulldomain_dot}\"" \
    | grep "\"type\":\"TXT\"" \
    | grep "${txtvalue}" \
    | _egrep_o "\"id\":\"[^\"]*\"" | cut -d '"' -f 4 | _head_n 1)

  if [ -z "$_record_id" ]; then
    _debug "No matching record found; nothing to clean up"
    return 0
  fi

  if ! _dnscale_rest DELETE "v1/zones/${_domain_id}/records/${_record_id}"; then
    _err "Could not delete TXT record"
    return 1
  fi

  _info "TXT record deleted successfully"
  return 0
}

####################  Private functions below ##################################

# Find the zone for a given domain.
# Sets _domain, _domain_id, _sub_domain.
_get_root() {
  domain=$1
  i=1
  p=1

  if ! _dnscale_rest GET "v1/zones?limit=100"; then
    return 1
  fi

  _zones_response="$response"

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)

    if [ -z "$h" ]; then
      return 1
    fi

    _debug "Checking if $h is a zone"

    if _contains "$_zones_response" "\"name\":\"$h\""; then
      # Split on '{' so each zone object becomes its own chunk,
      # then find the chunk containing the zone name and extract the id.
      # Robust to the API's wrapped {"status":"success","data":{"zones":[...]}} shape
      # and any future field ordering changes.
      _domain_id=$(echo "$_zones_response" | tr '{' '\n' | grep "\"name\":\"$h\"" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d '"' -f 4 | _head_n 1)
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

# Make API requests to DNScale.
# Usage: _dnscale_rest METHOD ENDPOINT [DATA]
_dnscale_rest() {
  m=$1
  ep=$2
  data=$3

  _dnscale_old_H1=$_H1
  _dnscale_old_H2=$_H2
  _dnscale_old_H3=$_H3
  _dnscale_has_H1="${_H1+1}"
  _dnscale_has_H2="${_H2+1}"
  _dnscale_has_H3="${_H3+1}"

  export _H1="Authorization: Bearer ${DNSCALE_Token}"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  if [ "$m" = "GET" ]; then
    response="$(_get "${DNSCALE_Api}/${ep}")"
  else
    response="$(_post "$data" "${DNSCALE_Api}/${ep}" "" "$m" "application/json")"
  fi

  ret="$?"
  if [ "$ret" != "0" ]; then
    _debug "API request failed"
    ret=1
  else
    # API responses wrap as {"status":"success","data":...} or
    # {"status":"error","error":{"code":"...","message":"..."}}.
    if _contains "$response" "\"status\":\"error\""; then
      _debug "API error response"
      _debug response "$response"
      ret=1
    else
      _debug2 response "$response"
      ret=0
    fi
  fi

  if [ -n "$_dnscale_has_H1" ]; then
    export _H1="$_dnscale_old_H1"
  else
    unset _H1
  fi

  if [ -n "$_dnscale_has_H2" ]; then
    export _H2="$_dnscale_old_H2"
  else
    unset _H2
  fi

  if [ -n "$_dnscale_has_H3" ]; then
    export _H3="$_dnscale_old_H3"
  else
    unset _H3
  fi

  return "$ret"
}
