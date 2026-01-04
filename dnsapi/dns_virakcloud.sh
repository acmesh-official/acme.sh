#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_virakcloud_info='VirakCloud DNS API
Site: VirakCloud.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_virakcloud
Options:
 VIRAKCLOUD_API_TOKEN VirakCloud API Bearer Token
'

VIRAKCLOUD_API_URL="https://public-api.virakcloud.com/dns"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
#Used to add txt record
dns_virakcloud_add() {
  fulldomain=$1
  txtvalue=$2

  VIRAKCLOUD_API_TOKEN="${VIRAKCLOUD_API_TOKEN:-$(_readaccountconf_mutable VIRAKCLOUD_API_TOKEN)}"

  if [ -z "$VIRAKCLOUD_API_TOKEN" ]; then
    _err "You haven't configured your VirakCloud API token yet."
    _err "Please set VIRAKCLOUD_API_TOKEN environment variable or run:"
    _err "  export VIRAKCLOUD_API_TOKEN=\"your-api-token\""
    return 1
  fi

  _saveaccountconf_mutable VIRAKCLOUD_API_TOKEN "$VIRAKCLOUD_API_TOKEN"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    http_code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
    if [ "$http_code" = "401" ]; then
      return 1
    fi
    _err "Invalid domain"
    return 1
  fi

  _debug _domain "$_domain"
  _debug fulldomain "$fulldomain"

  _info "Adding TXT record"

  if _virakcloud_rest POST "domains/${_domain}/records" "{\"record\":\"${fulldomain}\",\"type\":\"TXT\",\"ttl\":3600,\"content\":\"${txtvalue}\"}"; then
    if echo "$response" | grep -q "success" || echo "$response" | grep -q "\"data\""; then
      _info "Added, OK"
      return 0
    elif echo "$response" | grep -q "already exists" || echo "$response" | grep -q "duplicate"; then
      _info "Record already exists, OK"
      return 0
    else
      _err "Add TXT record error."
      _err "Response: $response"
      return 1
    fi
  fi

  _err "Add TXT record error."
  return 1
}

#Usage: fulldomain txtvalue
#Used to remove the txt record after validation
dns_virakcloud_rm() {
  fulldomain=$1
  txtvalue=$2

  VIRAKCLOUD_API_TOKEN="${VIRAKCLOUD_API_TOKEN:-$(_readaccountconf_mutable VIRAKCLOUD_API_TOKEN)}"

  if [ -z "$VIRAKCLOUD_API_TOKEN" ]; then
    _err "You haven't configured your VirakCloud API token yet."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    http_code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
    if [ "$http_code" = "401" ]; then
      return 1
    fi
    _err "Invalid domain"
    return 1
  fi

  _debug _domain "$_domain"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _info "Removing TXT record"

  _debug "Getting list of records to find content ID"
  if ! _virakcloud_rest GET "domains/${_domain}/records" ""; then
    return 1
  fi

  _debug2 "Records response" "$response"

  contentid=""
  # Extract innermost objects (content objects) which look like {"id":"...","content_raw":"..."}
  # We filter for the one containing txtvalue

  target_obj=$(echo "$response" | grep -o '{[^}]*}' | grep "$txtvalue" | _head_n 1)

  if [ -n "$target_obj" ]; then
    contentid=$(echo "$target_obj" | _egrep_o '"id":"[^"]*"' | cut -d '"' -f 4)
  fi

  if [ -z "$contentid" ]; then
    _debug "Could not find matching record ID in response"
    _info "Record not found, may have been already removed"
    return 0
  fi

  _debug contentid "$contentid"

  if _virakcloud_rest DELETE "domains/${_domain}/records/${fulldomain}/TXT/${contentid}" ""; then
    if echo "$response" | grep -q "success" || [ -z "$response" ]; then
      _info "Removed, OK"
      return 0
    elif echo "$response" | grep -q "not found" || echo "$response" | grep -q "404"; then
      _info "Record not found, OK"
      return 0
    else
      _err "Remove TXT record error."
      _err "Response: $response"
      return 1
    fi
  fi

  _err "Remove TXT record error."
  return 1
}

####################  Private functions below ##################################

#_acme-challenge.www.domain.com
#returns
# _domain=domain.com
_get_root() {
  domain=$1
  i=1
  p=1

  # Optimization: skip _acme-challenge subdomain to avoid 422 errors
  if echo "$domain" | grep -q "^_acme-challenge."; then
    i=2
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"

    if [ -z "$h" ]; then
      return 1
    fi

    if ! _virakcloud_rest GET "domains/$h" ""; then
      http_code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
      if [ "$http_code" = "401" ]; then
        return 1
      fi
      p=$i
      i=$(_math "$i" + 1)
      continue
    fi

    if echo "$response" | grep -q "\"name\""; then
      _domain="$h"
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}

_virakcloud_rest() {
  m=$1
  ep="$2"
  data="$3"

  _debug "$ep"

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $VIRAKCLOUD_API_TOKEN"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$VIRAKCLOUD_API_URL/$ep" "" "$m")"
  else
    response="$(_get "$VIRAKCLOUD_API_URL/$ep")"
  fi

  _ret="$?"

  if [ "$_ret" != "0" ]; then
    _err "error on $m $ep"
    return 1
  fi

  http_code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
  _debug "http response code" "$http_code"

  if [ "$http_code" = "401" ]; then
    _err "VirakCloud API returned 401 Unauthorized."
    _err "Your VIRAKCLOUD_API_TOKEN is invalid or expired."
    _err "Please check your API token and try again."
    return 1
  fi

  if [ "$http_code" = "403" ]; then
    _err "VirakCloud API returned 403 Forbidden."
    _err "Your API token does not have permission to access this resource."
    return 1
  fi

  if [ -n "$http_code" ] && [ "$http_code" -ge 400 ]; then
    _err "VirakCloud API error. HTTP code: $http_code"
    _err "Response: $response"
    return 1
  fi

  _debug2 response "$response"
  return 0
}
