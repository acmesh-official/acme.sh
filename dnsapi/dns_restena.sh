#!/usr/bin/env sh

# shellcheck disable=SC2034
dns_restena_info='RESTENA DNS
Site: dnsgui.restena.lu
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_restena
Options:
 RESTENA_TOKEN API token
Issues: github.com/acmesh-official/acme.sh/issues/7265
Author: Steve Clement <https://github.com/SteveClement>
'

RESTENA_API="https://dnsgui.restena.lu/json.php"

######## Public functions #####################

# Usage: dns_restena_add _acme-challenge.www.example.lu "challenge-value"
dns_restena_add() {
  fulldomain=$1
  txtvalue=$2

  RESTENA_TOKEN="${RESTENA_TOKEN:-$(_readaccountconf_mutable RESTENA_TOKEN)}"
  if [ -z "$RESTENA_TOKEN" ]; then
    RESTENA_TOKEN=""
    _err "RESTENA_TOKEN is not set."
    _err "Create a RESTENA DNS API token, export RESTENA_TOKEN, and try again."
    return 1
  fi
  _saveaccountconf_mutable RESTENA_TOKEN "$RESTENA_TOKEN"

  if ! _restena_get_root "$fulldomain"; then
    _err "Unable to determine the RESTENA-hosted zone for $fulldomain."
    return 1
  fi

  _debug _restena_sub_domain "$_restena_sub_domain"
  _debug _restena_domain "$_restena_domain"

  _restena_data="\\\"$txtvalue\\\""
  _restena_body="{\"token\":\"$RESTENA_TOKEN\",\"zone\":\"$_restena_domain\",\"label\":\"$_restena_sub_domain\",\"type\":\"TXT\",\"data\":\"$_restena_data\"}"

  _info "Adding TXT record for $fulldomain using the RESTENA DNS API."
  if ! _restena_request PUT "$_restena_body"; then
    _err "RESTENA API request failed while adding $fulldomain."
    _err "$_restena_response"
    return 1
  fi

  _restena_track_add "$fulldomain"

  return 0
}

# Usage: dns_restena_rm _acme-challenge.www.example.lu "challenge-value"
dns_restena_rm() {
  fulldomain=$1
  txtvalue=$2

  RESTENA_TOKEN="${RESTENA_TOKEN:-$(_readaccountconf_mutable RESTENA_TOKEN)}"
  if [ -z "$RESTENA_TOKEN" ]; then
    RESTENA_TOKEN=""
    _err "RESTENA_TOKEN is not set."
    return 1
  fi

  if ! _restena_get_root "$fulldomain"; then
    _err "Unable to determine the RESTENA-hosted zone for $fulldomain."
    return 1
  fi

  _debug _restena_sub_domain "$_restena_sub_domain"
  _debug _restena_domain "$_restena_domain"

  _restena_data="\\\"$txtvalue\\\""
  _restena_body="{\"token\":\"$RESTENA_TOKEN\",\"zone\":\"$_restena_domain\",\"label\":\"$_restena_sub_domain\",\"type\":\"TXT\",\"data\":\"$_restena_data\"}"

  _info "Removing TXT record for $fulldomain using the RESTENA DNS API."
  if _restena_defer_remove "$fulldomain"; then
    _info "Other TXT values from this ACME order still use $fulldomain; deferring RESTENA cleanup."
    return 0
  fi

  if _restena_request DELETE "$_restena_body"; then
    _restena_clear_state "$fulldomain"
    return 0
  fi

  if [ "$_restena_code" = "404" ] && _contains "$_restena_response" "No record found to delete"; then
    _info "TXT record for $fulldomain is already absent."
    _restena_clear_state "$fulldomain"
    return 0
  fi

  _err "RESTENA API request failed while removing $fulldomain."
  _err "$_restena_response"
  return 1
}

######## Private functions ####################

# Find the nearest enclosing DNS zone whose authoritative servers are RESTENA.
# Returns _restena_sub_domain and _restena_domain.
_restena_get_root() {
  _restena_full_domain=$1
  _restena_i=1
  _restena_p=1

  while true; do
    _restena_h=$(printf "%s" "$_restena_full_domain" | cut -d . -f "$_restena_i"-100)
    if [ -z "$_restena_h" ]; then
      return 1
    fi

    _restena_ns=$(_ns_lookup "$_restena_h" NS)
    if _contains "$_restena_ns" ".restena.lu."; then
      _restena_sub_domain=$(printf "%s" "$_restena_full_domain" | cut -d . -f 1-"$_restena_p")
      _restena_domain=$_restena_h
      return 0
    fi

    _restena_p=$_restena_i
    _restena_i=$(_math "$_restena_i" + 1)
  done
}

_restena_request() {
  _restena_method=$1
  _restena_payload=$2

  export _H1="Content-Type: application/json"
  _restena_response=$(_post "$_restena_payload" "$RESTENA_API" "" "$_restena_method")
  _restena_ret=$?
  _restena_code=$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")
  _debug _restena_code "$_restena_code"
  _debug2 _restena_response "$_restena_response"

  if [ "$_restena_ret" != "0" ]; then
    return 1
  fi

  case $_restena_code in
  2??) return 0 ;;
  esac
  return 1
}

# RESTENA DELETE operates on label and type, and removes all matching values.
# Keep a per-order count so wildcard and base-domain challenges sharing a label
# are deleted only after the final cleanup call.
_restena_track_add() {
  _restena_load_state "$1"
  if [ "$_restena_saved_run" != "$_restena_current_run" ]; then
    _restena_count=0
  fi
  _restena_count=$(_math "$_restena_count" + 1)
  _savedomainconf "$_restena_run_key" "$_restena_current_run"
  _savedomainconf "$_restena_count_key" "$_restena_count"
  _info "RESTENA cleanup state for $1: $_restena_count active value(s)."
}

# Return success when deletion must be deferred; failure when this is the final
# value (or when no reliable state is available and cleanup should be tried).
_restena_defer_remove() {
  _restena_load_state "$1"
  if [ "$_restena_saved_run" = "$_restena_current_run" ] && [ "$_restena_count" -gt 1 ]; then
    _restena_count=$(_math "$_restena_count" - 1)
    _savedomainconf "$_restena_count_key" "$_restena_count"
    _info "RESTENA cleanup state for $1: $_restena_count active value(s) remain."
    return 0
  fi
  return 1
}

_restena_clear_state() {
  _restena_state_keys "$1"
  _cleardomainconf "$_restena_run_key"
  _cleardomainconf "$_restena_count_key"
}

_restena_load_state() {
  _restena_state_keys "$1"
  _restena_saved_run=$(_readdomainconf "$_restena_run_key")
  _restena_count=$(_readdomainconf "$_restena_count_key")
  case $_restena_count in
  '' | *[!0-9]*) _restena_count=0 ;;
  esac
}

_restena_state_keys() {
  _restena_state_hash=$(printf "%s" "$1" | _digest sha256 | cut -c 1-16)
  _restena_current_run=$(printf "%s" "$$" | _digest sha256)
  _restena_run_key="RESTENA_RUN_$_restena_state_hash"
  _restena_count_key="RESTENA_COUNT_$_restena_state_hash"
}
