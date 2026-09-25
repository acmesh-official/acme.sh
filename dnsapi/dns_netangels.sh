#!/usr/bin/env sh

# NetAngels (netangels.ru) DNS API hook for acme.sh
#
# Usage:
#   export NETANGELS_API_KEY="xxx"
#   acme.sh --issue --dns dns_netangels -d example.com --dnssleep 130
#
# The API key is obtained from the NetAngels control panel
# (https://panel.netangels.ru/account/api/).
#
# NetAngels API notes:
#   - Auth: POST https://panel.netangels.ru/api/gateway/token/ with
#     api_key=... -> JWT token (Bearer), valid 24h.
#   - Records are created via the flat endpoint POST /api/v1/dns/records/
#     with a FULLY QUALIFIED "name" (not relative to the zone) - the API
#     infers the zone from the longest matching suffix. The zone-scoped
#     endpoint POST /api/v1/dns/zones/{id}/records/ does not support
#     creation (returns "Метод не поддерживается", i.e. "Method not
#     supported") - only GET (list) works there.
#   - ttl must be in the range [300, 2147483647]; values below 300 are
#     rejected.
#   - Record deletion is DELETE /api/v1/dns/records/{id}/ (flat, by
#     record id).
#   - Propagation from an API write to the actual nameservers
#     (ns1-4.netangels.ru) is asynchronous and can take 120s or more.
#     Use --dnssleep 130 or higher when calling acme.sh.

NETANGELS_TOKEN_URL="https://panel.netangels.ru/api/gateway/token/"
NETANGELS_API="https://api-ms.netangels.ru/api/v1/dns"

########  Public functions #####################

#Usage: dns_netangels_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_netangels_add() {
  fulldomain=$1
  txtvalue=$2

  _netangels_load_key || return 1

  _info "Getting NetAngels API token"
  _netangels_get_token || return 1

  _info "Creating TXT record for $fulldomain"
  body="{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"value\":\"$txtvalue\",\"ttl\":300}"
  export _H1="Authorization: Bearer $NETANGELS_TOKEN"
  export _H2="Content-Type: application/json"
  response="$(_post "$body" "$NETANGELS_API/records/" "" "POST")"
  _debug2 "create response" "$response"

  if ! _contains "$response" '"id"'; then
    _err "NetAngels: failed to create TXT record: $response"
    return 1
  fi

  rec_id=$(echo "$response" | tr -d '\n' | sed -n 's/.*"id":[[:space:]]*\([0-9]*\).*/\1/p')
  _info "Created record id $rec_id (propagation is async, use --dnssleep 130 or higher)"
  _savedomainconf "NETANGELS_REC_ID_$(_netangels_varname "$fulldomain")" "$rec_id"
  return 0
}

#Usage: dns_netangels_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_netangels_rm() {
  fulldomain=$1
  txtvalue=$2

  _netangels_load_key || return 1
  _netangels_get_token || return 1

  rec_id=$(_readdomainconf "NETANGELS_REC_ID_$(_netangels_varname "$fulldomain")")

  if [ -z "$rec_id" ]; then
    _info "No stored record id for $fulldomain, nothing to remove"
    return 0
  fi

  _info "Deleting TXT record id $rec_id for $fulldomain"
  export _H1="Authorization: Bearer $NETANGELS_TOKEN"
  _post "" "$NETANGELS_API/records/$rec_id/" "" "DELETE" >/dev/null
  return 0
}

########  Private functions ##################

# Config-safe variable name from a domain (dots/dashes -> underscore).
# Portable equivalent of the bash-only ${var//[.-]/_} substitution.
_netangels_varname() {
  echo "$1" | sed 's/[.-]/_/g'
}

_netangels_load_key() {
  NETANGELS_API_KEY="${NETANGELS_API_KEY:-$(_readaccountconf_mutable NETANGELS_API_KEY)}"
  if [ -z "$NETANGELS_API_KEY" ]; then
    _err "NETANGELS_API_KEY is not set. Please export NETANGELS_API_KEY=<your api key>"
    return 1
  fi
  _saveaccountconf_mutable NETANGELS_API_KEY "$NETANGELS_API_KEY"
  return 0
}

_netangels_get_token() {
  token_response="$(_post "api_key=$NETANGELS_API_KEY" "$NETANGELS_TOKEN_URL")"
  NETANGELS_TOKEN=$(echo "$token_response" | tr -d '\n' | sed -n 's/.*"token":[[:space:]]*"\([^"]*\)".*/\1/p')
  if [ -z "$NETANGELS_TOKEN" ]; then
    _err "Failed to obtain API token: $token_response"
    return 1
  fi
  return 0
}
