#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_nsin_info='nsin.ir
Site: nsin.ir
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_nsin
Options:
 NSIN_Api_Key API Key. Create one in the panel: https://panel.nsin.ir/settings/api-keys (must NOT be read-only)
Issues: github.com/acmesh-official/acme.sh/issues
Author: nsin
'

# Default REST endpoint. Override with NSIN_Api for self-hosted / staging.
NSIN_Api_Default="https://api.nsin.ir"

########  Public functions #####################

# Usage: dns_nsin_add   _acme-challenge.www.example.com   "TXT_value"
dns_nsin_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _nsin_load_config; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  _info "Adding TXT record"
  _data="{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"destination\":\"$txtvalue\"}"
  if _nsin_rest POST "domains/$_domain/records/" "$_data"; then
    if _contains "$response" "\"id\":"; then
      _info "Added, OK"
      return 0
    fi
  fi
  _err "Add txt record error: $response"
  return 1
}

# Usage: dns_nsin_rm   _acme-challenge.www.example.com   "TXT_value"
dns_nsin_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _nsin_load_config; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  _info "Getting records to find the one to remove"
  if ! _nsin_rest GET "domains/$_domain/records/"; then
    _err "Could not list records: $response"
    return 1
  fi

  # Each TXT is a separate record row: find the row whose destination is our
  # value and pull its numeric id. id precedes destination inside the same
  # object, and [^}] keeps the match from spilling into the next record.
  _record_id=$(echo "$response" | _egrep_o "\"id\":[0-9]+[^}]*\"destination\":\"$txtvalue\"" | _egrep_o "\"id\":[0-9]+" | cut -d : -f 2 | head -n 1)
  _debug _record_id "$_record_id"
  if [ -z "$_record_id" ]; then
    _info "No matching TXT record found, nothing to remove"
    return 0
  fi

  _info "Removing record $_record_id"
  if _nsin_rest DELETE "domains/$_domain/records/$_record_id"; then
    _info "Removed, OK"
    return 0
  fi
  _err "Remove txt record error: $response"
  return 1
}

####################  Private functions below ##################################

_nsin_load_config() {
  NSIN_Api_Key="${NSIN_Api_Key:-$(_readaccountconf_mutable NSIN_Api_Key)}"
  NSIN_Api="${NSIN_Api:-$(_readaccountconf_mutable NSIN_Api)}"

  if [ -z "$NSIN_Api_Key" ]; then
    NSIN_Api_Key=""
    _err "You didn't specify the nsin API key \"NSIN_Api_Key\" yet."
    _err "Create one (not read-only) at https://panel.nsin.ir/settings/api-keys"
    return 1
  fi
  case "$NSIN_Api_Key" in
  nsin_*) ;;
  *)
    _err "NSIN_Api_Key does not look like an nsin key (should start with nsin_)."
    return 1
    ;;
  esac

  if [ -z "$NSIN_Api" ]; then
    NSIN_Api="$NSIN_Api_Default"
  fi

  # Persist for renewals; only save the base URL when it isn't the default.
  _saveaccountconf_mutable NSIN_Api_Key "$NSIN_Api_Key"
  if [ "$NSIN_Api" != "$NSIN_Api_Default" ]; then
    _saveaccountconf_mutable NSIN_Api "$NSIN_Api"
  else
    _clearaccountconf_mutable NSIN_Api
  fi
  return 0
}

# Walk the labels of the fulldomain against the account's domain list to find
# the registrable zone (_domain) and the record name relative to it
# (_sub_domain). The domain list is fetched once and matched locally.
_get_root() {
  domain=$1
  i=1
  p=1

  if ! _nsin_rest GET "domains/"; then
    _err "Could not list domains. Check NSIN_Api_Key."
    return 1
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      # not found
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain="$h"
      return 0
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

# _nsin_rest  METHOD  path  [body]
# Sets $response; returns non-zero on transport error or an HTTP error body.
_nsin_rest() {
  m="$1"
  ep="$2"
  data="$3"

  export _H1="X-Api-Key: $NSIN_Api_Key"
  _url="$NSIN_Api/$ep"
  _debug "$m" "$_url"

  if [ "$m" = "GET" ]; then
    response="$(_get "$_url")"
  else
    _debug data "$data"
    response="$(_post "$data" "$_url" "" "$m" "application/json")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $m $_url"
    return 1
  fi
  _debug2 response "$response"

  # API errors come back as {"error":"..."} with a non-2xx status.
  if _contains "$response" "\"error\":"; then
    return 1
  fi
  return 0
}
