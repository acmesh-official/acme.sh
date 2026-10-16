#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_dnscale_info='DNScale DNS API
 DNScale authoritative DNS hosting.
 Requires an API token with zones:read, records:read and records:write scopes.
Domains: dnscale.eu
Site: dnscale.eu
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_dnscale
Options:
 DNSCALE_Token API Token. Create one at app.dnscale.eu with zones:read, records:read and records:write scopes.
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
    _err "Create one at https://app.dnscale.eu with zones:read, records:read and records:write scopes."
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
  _record_name="$(_dnscale_json_escape "$_sub_domain")"
  _record_content="$(_dnscale_json_escape "$txtvalue")"
  if ! _dnscale_rest POST "v1/zones/${_domain_id}/records" "{\"name\":\"${_record_name}\",\"type\":\"TXT\",\"content\":\"${_record_content}\",\"ttl\":300}"; then
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

  _record_name="$(printf "%s" "$_sub_domain" | _url_encode)"
  _record_content="$(printf "%s" "$txtvalue" | _url_encode)"
  if ! _dnscale_rest DELETE "v1/zones/${_domain_id}/records/by-name/${_record_name}/TXT?content=${_record_content}"; then
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
        if [ "$h" = "$domain" ]; then
          _sub_domain="@"
        else
          _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        fi
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

_dnscale_json_escape() {
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Make API requests to DNScale.
# Usage: _dnscale_rest METHOD ENDPOINT [DATA]
_dnscale_rest() {
  m=$1
  ep=$2
  data=${3:-}

  _dnscale_old_H1="${_H1-}"
  _dnscale_old_H2="${_H2-}"
  _dnscale_old_H3="${_H3-}"
  _dnscale_old_H4="${_H4-}"
  _dnscale_old_H5="${_H5-}"
  _dnscale_has_H1="${_H1+x}"
  _dnscale_has_H2="${_H2+x}"
  _dnscale_has_H3="${_H3+x}"
  _dnscale_has_H4="${_H4+x}"
  _dnscale_has_H5="${_H5+x}"

  export _H1="Authorization: Bearer ${DNSCALE_Token}"
  export _H2="Accept: application/json"
  unset _H3
  unset _H4
  unset _H5

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
    response="$(printf "%s" "$response" | _normalizeJson)"
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

  if [ "$_dnscale_has_H1" ]; then
    export _H1="$_dnscale_old_H1"
  else
    unset _H1
  fi

  if [ "$_dnscale_has_H2" ]; then
    export _H2="$_dnscale_old_H2"
  else
    unset _H2
  fi

  if [ "$_dnscale_has_H3" ]; then
    export _H3="$_dnscale_old_H3"
  else
    unset _H3
  fi

  if [ "$_dnscale_has_H4" ]; then
    export _H4="$_dnscale_old_H4"
  else
    unset _H4
  fi

  if [ "$_dnscale_has_H5" ]; then
    export _H5="$_dnscale_old_H5"
  else
    unset _H5
  fi

  return "$ret"
}
